use super::{
    server::{Ripple, EVENT_PROXY},
    win_linux::{create_font_face, draw_text},
    Cursor, CustomEvent, DrawItem, Shape, ShapeKind,
};
use hbb_common::{anyhow::anyhow, log, ResultType};
use softbuffer::{Context, Surface};
use std::{collections::HashMap, num::NonZeroU32, sync::Arc, time::Instant};
use tao::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoopBuilder},
    platform::windows::WindowBuilderExtWindows,
    window::WindowBuilder,
};
use tiny_skia::{
    BlendMode, Color, FillRule, LineCap, Paint, Path, PathBuilder, PixmapMut, Rect, Stroke,
    Transform,
};

/// O caminho de uma forma, em pixels do desktop capturado.
///
/// Os dois pontos são cantos OPOSTOS e chegam na ordem em que o técnico
/// arrastou, que pode ser da direita para a esquerda ou de baixo para cima —
/// daí o min/max antes de montar o retângulo. A seta é a única que se importa
/// com a ordem: ela aponta para onde o arrasto terminou.
fn build_shape_path(shape: &Shape, canvas_w: f32, canvas_h: f32) -> Option<Path> {
    let x0 = shape.x0.clamp(0.0, 1.0) * canvas_w;
    let y0 = shape.y0.clamp(0.0, 1.0) * canvas_h;
    let x1 = shape.x1.clamp(0.0, 1.0) * canvas_w;
    let y1 = shape.y1.clamp(0.0, 1.0) * canvas_h;

    let mut pb = PathBuilder::new();
    match shape.kind {
        ShapeKind::Rect => {
            let (l, t) = (x0.min(x1), y0.min(y1));
            let (r, b) = (x0.max(x1), y0.max(y1));
            pb.move_to(l, t);
            pb.line_to(r, t);
            pb.line_to(r, b);
            pb.line_to(l, b);
            pb.close();
        }
        ShapeKind::Ellipse => {
            // `Rect::from_ltrb` recusa retângulo vazio, e um clique sem
            // arrasto produz exatamente isso. Sem a guarda, a forma sumiria
            // silenciosamente em vez de virar um ponto.
            let rect = Rect::from_ltrb(x0.min(x1), y0.min(y1), x0.max(x1), y0.max(y1))?;
            pb.push_oval(rect);
        }
        ShapeKind::Line => {
            pb.move_to(x0, y0);
            pb.line_to(x1, y1);
        }
        ShapeKind::Arrow => {
            pb.move_to(x0, y0);
            pb.line_to(x1, y1);
            let dx = x1 - x0;
            let dy = y1 - y0;
            let len = (dx * dx + dy * dy).sqrt();
            if len > 1.0 {
                // A farpa acompanha a espessura do traço, senão a seta fica
                // com ponta de alfinete quando o pincel está grosso.
                let barb = (shape.width * 4.0).clamp(10.0, len * 0.5);
                let (ux, uy) = (dx / len, dy / len);
                let angle = 0.5f32;
                let (sin, cos) = angle.sin_cos();
                for sign in [1.0f32, -1.0] {
                    let rx = ux * cos + uy * (sin * sign);
                    let ry = uy * cos - ux * (sin * sign);
                    pb.move_to(x1, y1);
                    pb.line_to(x1 - rx * barb, y1 - ry * barb);
                }
            }
        }
    }
    pb.finish()
}

pub(super) fn create_event_loop() -> ResultType<()> {
    let face = match create_font_face() {
        Ok(face) => Some(face),
        Err(err) => {
            log::error!("Failed to create font face: {}", err);
            None
        }
    };

    let event_loop = EventLoopBuilder::<(String, CustomEvent)>::with_user_event().build();
    let mut window_builder = WindowBuilder::new()
        .with_title("RustDesk whiteboard")
        .with_transparent(true)
        .with_always_on_top(true)
        .with_skip_taskbar(true)
        .with_decorations(false);

    let mut final_size = None;
    if let Ok((x, y, w, h)) = super::server::get_displays_rect() {
        if w > 0 && h > 0 {
            final_size = Some(PhysicalSize::new(w, h));
            window_builder = window_builder
                .with_position(PhysicalPosition::new(x, y))
                .with_inner_size(PhysicalSize::new(1, 1));
        } else {
            window_builder =
                window_builder.with_fullscreen(Some(tao::window::Fullscreen::Borderless(None)));
        }
    } else {
        window_builder =
            window_builder.with_fullscreen(Some(tao::window::Fullscreen::Borderless(None)));
    }

    let window = Arc::new(window_builder.build::<(String, CustomEvent)>(&event_loop)?);
    window.set_ignore_cursor_events(true)?;

    let context = Context::new(window.clone()).map_err(|e| {
        log::error!("Failed to create context: {}", e);
        anyhow!(e.to_string())
    })?;
    let mut surface = Surface::new(&context, window.clone()).map_err(|e| {
        log::error!("Failed to create surface: {}", e);
        anyhow!(e.to_string())
    })?;

    let proxy = event_loop.create_proxy();
    EVENT_PROXY.write().unwrap().replace(proxy);
    let _call_on_ret = crate::common::SimpleCallOnReturn {
        b: true,
        f: Box::new(move || {
            let _ = EVENT_PROXY.write().unwrap().take();
        }),
    };

    let mut ripples: Vec<Ripple> = Vec::new();
    let mut last_cursors: HashMap<String, Cursor> = HashMap::new();
    let mut drawings: HashMap<String, Vec<DrawItem>> = HashMap::new();
    let mut resized = final_size.is_none();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;

        match event {
            Event::WindowEvent { event, .. } => match event {
                WindowEvent::CloseRequested => {
                    *control_flow = ControlFlow::Exit;
                }
                _ => {}
            },
            Event::RedrawRequested(_) => {
                if !resized {
                    if let Some(size) = final_size.take() {
                        window.set_inner_size(size);
                    }
                    resized = true;
                    return;
                }

                let (width, height) = {
                    let size = window.inner_size();
                    (size.width, size.height)
                };

                let (Some(width), Some(height)) = (NonZeroU32::new(width), NonZeroU32::new(height))
                else {
                    return;
                };
                if let Err(e) = surface.resize(width, height) {
                    log::error!("Failed to resize surface: {}", e);
                    return;
                }

                let mut buffer = match surface.buffer_mut() {
                    Ok(buf) => buf,
                    Err(e) => {
                        log::error!("Failed to get buffer: {}", e);
                        return;
                    }
                };
                let Some(mut pixmap) = PixmapMut::from_bytes(
                    bytemuck::cast_slice_mut(&mut buffer),
                    width.get(),
                    height.get(),
                ) else {
                    log::error!("Failed to create pixmap from buffer");
                    return;
                };
                pixmap.fill(Color::TRANSPARENT);

                let canvas_w = width.get() as f32;
                let canvas_h = height.get() as f32;
                for items in drawings.values() {
                    for item in items {
                        let (path, argb, line_width, erase) = match item {
                            DrawItem::Stroke(segment) => {
                                let mut pb = PathBuilder::new();
                                pb.move_to(
                                    segment.x0.clamp(0.0, 1.0) * canvas_w,
                                    segment.y0.clamp(0.0, 1.0) * canvas_h,
                                );
                                pb.line_to(
                                    segment.x1.clamp(0.0, 1.0) * canvas_w,
                                    segment.y1.clamp(0.0, 1.0) * canvas_h,
                                );
                                (pb.finish(), segment.argb, segment.width, segment.erase)
                            }
                            DrawItem::Shape(shape) => (
                                build_shape_path(shape, canvas_w, canvas_h),
                                shape.argb,
                                shape.width,
                                false,
                            ),
                        };
                        if let Some(path) = path {
                            let rgba = super::argb_to_rgba(argb);
                            let mut paint = Paint::default();
                            paint.set_color_rgba8(rgba.2, rgba.1, rgba.0, rgba.3);
                            paint.anti_alias = true;
                            if erase {
                                paint.blend_mode = BlendMode::Clear;
                            }
                            let mut stroke = Stroke::default();
                            stroke.width = line_width.clamp(1.0, 60.0);
                            stroke.line_cap = LineCap::Round;
                            pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
                        }
                    }
                }

                Ripple::retain_active(&mut ripples);
                for ripple in &ripples {
                    let (radius, alpha) = ripple.get_radius_alpha();

                    let mut ripple_paint = Paint::default();
                    // Note: The real color is bgra here.
                    ripple_paint.set_color_rgba8(64, 64, 255, (alpha * 128.0) as u8);
                    ripple_paint.anti_alias = true;

                    let mut ripple_pb = PathBuilder::new();
                    ripple_pb.push_circle(ripple.x, ripple.y, radius);
                    if let Some(path) = ripple_pb.finish() {
                        pixmap.fill_path(
                            &path,
                            &ripple_paint,
                            FillRule::Winding,
                            Transform::identity(),
                            None,
                        );
                    }
                }

                for cursor in last_cursors.values() {
                    let (x, y) = (cursor.x, cursor.y);
                    let size = 1.5f32;

                    let mut pb = PathBuilder::new();
                    pb.move_to(x, y);
                    pb.line_to(x, y + 16.0 * size);
                    pb.line_to(x + 4.0 * size, y + 13.0 * size);
                    pb.line_to(x + 7.0 * size, y + 20.0 * size);
                    pb.line_to(x + 9.0 * size, y + 19.0 * size);
                    pb.line_to(x + 6.0 * size, y + 12.0 * size);
                    pb.line_to(x + 11.0 * size, y + 12.0 * size);
                    pb.close();

                    if let Some(path) = pb.finish() {
                        let rgba = super::argb_to_rgba(cursor.argb);
                        let mut arrow_paint = Paint::default();
                        // Note: The real color is bgra here.
                        arrow_paint.set_color_rgba8(rgba.2, rgba.1, rgba.0, rgba.3);
                        arrow_paint.anti_alias = true;
                        pixmap.fill_path(
                            &path,
                            &arrow_paint,
                            FillRule::Winding,
                            Transform::identity(),
                            None,
                        );

                        let mut black_paint = Paint::default();
                        black_paint.set_color_rgba8(0, 0, 0, 255);
                        black_paint.anti_alias = true;
                        let mut stroke = Stroke::default();
                        stroke.width = 1.0f32;
                        pixmap.stroke_path(
                            &path,
                            &black_paint,
                            &stroke,
                            Transform::identity(),
                            None,
                        );

                        face.as_ref().map(|face| {
                            draw_text(
                                &mut pixmap,
                                face,
                                &cursor.text,
                                x + 24.0 * size,
                                y + 24.0 * size,
                                &arrow_paint,
                                14.0f32,
                            );
                        });
                    }
                }

                if let Err(e) = buffer.present() {
                    log::error!("Failed to present surface: {}", e);
                    return;
                }
            }
            Event::MainEventsCleared => {
                window.request_redraw();
            }
            Event::UserEvent((k, evt)) => match evt {
                CustomEvent::Cursor(cursor) => {
                    if cursor.btns != 0 {
                        ripples.push(Ripple {
                            x: cursor.x,
                            y: cursor.y,
                            start_time: Instant::now(),
                        });
                    }
                    last_cursors.insert(k, cursor);
                }
                CustomEvent::Stroke(segment) => {
                    let items = drawings.entry(k).or_default();
                    if items.len() >= 20_000 {
                        items.drain(..5_000);
                    }
                    items.push(DrawItem::Stroke(segment));
                }
                CustomEvent::Shape(shape) => {
                    let items = drawings.entry(k).or_default();
                    if items.len() >= 20_000 {
                        items.drain(..5_000);
                    }
                    items.push(DrawItem::Shape(shape));
                }
                CustomEvent::UndoDrawing => {
                    // Remove o último GRUPO, não o último item: um traço à mão
                    // livre chega como dezenas de segmentos, e tirar um só
                    // pareceria que o desfazer não fez nada.
                    if let Some(items) = drawings.get_mut(&k) {
                        if let Some(last) = items.last().map(|i| i.group()) {
                            items.retain(|i| i.group() != last);
                        }
                        if items.is_empty() {
                            drawings.remove(&k);
                        }
                    }
                }
                CustomEvent::ClearDrawing => {
                    drawings.remove(&k);
                }
                CustomEvent::Clear => {
                    drawings.remove(&k);
                    last_cursors.remove(&k);
                }
                CustomEvent::Exit => {
                    *control_flow = ControlFlow::Exit;
                }
            },
            _ => (),
        }
    });
}
