use serde_derive::{Deserialize, Serialize};

mod client;
mod server;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(any(target_os = "windows", target_os = "linux"))]
mod win_linux;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
pub use linux::is_supported;
#[cfg(target_os = "macos")]
use macos::create_event_loop;
#[cfg(target_os = "windows")]
use windows::create_event_loop;

pub use client::*;
pub use server::*;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum CustomEvent {
    Cursor(Cursor),
    Stroke(StrokeSegment),
    Shape(Shape),
    /// Desfaz o último item desenhado — o traço inteiro, não o segmento solto.
    UndoDrawing,
    ClearDrawing,
    Clear,
    Exit,
}

/// Um item do desenho, na ordem em que foi pintado.
///
/// Traços e formas moram na MESMA lista de propósito: a ordem entre eles é o
/// que o técnico vê, e separá-los em duas listas faria uma forma criada depois
/// aparecer por baixo de um traço criado antes.
#[derive(Debug, Clone)]
pub enum DrawItem {
    Stroke(StrokeSegment),
    Shape(Shape),
}

impl DrawItem {
    /// A que unidade de desfazer este item pertence.
    pub fn group(&self) -> u32 {
        match self {
            DrawItem::Stroke(s) => s.group,
            DrawItem::Shape(s) => s.group,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq)]
pub enum ShapeKind {
    Rect,
    Ellipse,
    Line,
    Arrow,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Shape {
    pub kind: ShapeKind,
    /// Cantos opostos, normalizados no desktop capturado (0.0 .. 1.0).
    pub x0: f32,
    pub y0: f32,
    pub x1: f32,
    pub y1: f32,
    pub argb: u32,
    pub width: f32,
    #[serde(default)]
    pub group: u32,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t")]
pub struct Cursor {
    pub x: f32,
    pub y: f32,
    pub argb: u32,
    pub btns: i32,
    pub text: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StrokeSegment {
    /// Normalized coordinates in the captured desktop (0.0 .. 1.0).
    pub x0: f32,
    pub y0: f32,
    pub x1: f32,
    pub y1: f32,
    pub argb: u32,
    pub width: f32,
    pub erase: bool,
    /// Todos os segmentos de um mesmo arrasto compartilham este número, e é
    /// por ele que o desfazer remove o traço INTEIRO em vez de um pedacinho.
    #[serde(default)]
    pub group: u32,
}
