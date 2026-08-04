import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'api_client.dart';
import 'theme.dart';

class BrandingPage extends StatefulWidget {
  const BrandingPage({super.key, this.technicianId, this.technicianName});

  final String? technicianId;
  final String? technicianName;

  @override
  State<BrandingPage> createState() => _BrandingPageState();
}

class _BrandingPageState extends State<BrandingPage> {
  final _name = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _removeLogo = false;
  bool _removeFavicon = false;
  Uint8List? _logo;
  Uint8List? _favicon;
  Uint8List? _faviconPreview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final branding = widget.technicianId == null
          ? await TgdeskApi.myBranding()
          : await TgdeskApi.technicianBranding(widget.technicianId!);
      final encoded = branding['logo_base64']?.toString() ?? '';
      final encodedFavicon = branding['favicon_base64']?.toString() ?? '';
      final favicon =
          encodedFavicon.isEmpty ? null : base64Decode(encodedFavicon);
      if (!mounted) return;
      setState(() {
        _enabled = branding['enabled'] == true;
        _name.text = branding['name']?.toString() ?? '';
        _logo = encoded.isEmpty ? null : base64Decode(encoded);
        _favicon = favicon;
        _faviconPreview = _previewBytes(favicon);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Uint8List? _previewBytes(Uint8List? bytes) {
    if (bytes == null) return null;
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.encodePng(decoded);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Selecionar logo',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (bytes.length > 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A logo deve possuir no máximo 1 MB.')),
        );
      }
      return;
    }
    final source = img.decodeImage(bytes);
    if (source == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir essa imagem.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final cropResult = await showDialog<_ImageCropResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImageCropDialog(
        source: source,
        brandName: _name.text,
        mode: _CropMode.logo,
      ),
    );
    if (cropResult == null) return;
    setState(() {
      _logo = cropResult.primary;
      _removeLogo = false;
    });
  }

  Future<void> _pickFavicon() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Selecionar imagem do ícone',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'ico'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final source = img.decodeImage(bytes);
    if (source == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir essa imagem.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final resultBytes = await showDialog<_ImageCropResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImageCropDialog(
        source: source,
        brandName: _name.text,
        mode: _CropMode.favicon,
      ),
    );
    if (resultBytes == null) return;
    setState(() {
      _favicon = resultBytes.primary;
      _faviconPreview = resultBytes.preview;
      _removeFavicon = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 40) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Use um nome entre 2 e 40 caracteres.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final encodedLogo =
          _logo == null || _removeLogo ? null : base64Encode(_logo!);
      final encodedFavicon =
          _favicon == null || _removeFavicon ? null : base64Encode(_favicon!);
      final branding = widget.technicianId == null
          ? await TgdeskApi.updateMyBranding(
              name, encodedLogo, _removeLogo, encodedFavicon, _removeFavicon)
          : await TgdeskApi.updateTechnicianBranding(widget.technicianId!, name,
              encodedLogo, _removeLogo, encodedFavicon, _removeFavicon);
      final encoded = branding['logo_base64']?.toString() ?? '';
      final returnedFavicon = branding['favicon_base64']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _logo = encoded.isEmpty ? null : base64Decode(encoded);
        _favicon =
            returnedFavicon.isEmpty ? null : base64Decode(returnedFavicon);
        _faviconPreview = _previewBytes(_favicon);
        _removeLogo = false;
        _removeFavicon = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Marca salva. Os clientes vinculados receberão a alteração em tempo real.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    if (!_enabled && widget.technicianId == null) {
      return const Center(
        child: Text('Personalização não habilitada pelo administrador.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
            widget.technicianId == null
                ? 'Identidade visual dos seus clientes'
                : 'Identidade visual de ${widget.technicianName ?? 'técnico'}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(widget.technicianId == null
            ? 'Esta marca aparece somente nos computadores client vinculados à sua organização. '
                'O seu painel técnico continua usando a identidade TGDesk.'
            : _enabled
                ? 'Como administrador, você pode configurar a mesma função disponível ao técnico.'
                : 'A marca está desabilitada para este técnico. Você pode prepará-la agora e habilitá-la na lista.'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 180,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xff091522),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                  alignment: Alignment.center,
                  child: _logo == null
                      ? const Icon(Icons.image_outlined, size: 42)
                      : Image.memory(_logo!, fit: BoxFit.contain),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Nome exibido ao cliente',
                          hintText: 'Ex.: BE-Desk',
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Escolher logo'),
                          ),
                          if (_logo != null)
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _logo = null;
                                _removeLogo = true;
                              }),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remover logo'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text('Ícone dos computadores Client',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text(
                        'Usado na janela, barra de tarefas, bandeja e demais ícones do Client.',
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 18,
                        runSpacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _faviconPreviewBox(64, 'Janela'),
                          _faviconPreviewBox(32, 'Tarefa'),
                          _faviconPreviewBox(16, 'Bandeja'),
                          OutlinedButton.icon(
                            onPressed: _pickFavicon,
                            icon: const Icon(Icons.crop_outlined),
                            label: Text(_favicon == null
                                ? 'Criar favicon'
                                : 'Editar enquadramento'),
                          ),
                          if (_favicon != null)
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _favicon = null;
                                _faviconPreview = null;
                                _removeFavicon = true;
                              }),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remover favicon'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: const Text('Salvar identidade visual'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _faviconPreviewBox(double size, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xff091522),
              borderRadius: BorderRadius.circular(size > 24 ? 10 : 4),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: _faviconPreview == null
                ? Icon(Icons.apps, size: size * .55)
                : Image.memory(_faviconPreview!, fit: BoxFit.cover),
          ),
          const SizedBox(height: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

enum _CropMode { favicon, logo }

class _ImageCropResult {
  const _ImageCropResult(this.primary, this.preview);
  // Favicon: `primary` is the multi-size .ico. Logo: `primary` is the PNG.
  final Uint8List primary;
  final Uint8List preview;
}

class _ImageCropDialog extends StatefulWidget {
  const _ImageCropDialog({
    required this.source,
    required this.brandName,
    required this.mode,
  });
  final img.Image source;
  final String brandName;
  final _CropMode mode;

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  // Real render size used by the client for the logo (see client_home_page.dart).
  static const int _logoRenderWidth = 72;
  static const int _logoRenderHeight = 25;
  static const int _logoPreviewScale = 4;

  double _zoom = 1;
  double _horizontal = 0;
  double _vertical = 0;
  late Uint8List _preview;
  late Uint8List _ico;

  bool get _isFavicon => widget.mode == _CropMode.favicon;

  double get _aspectRatio =>
      _isFavicon ? 1 : _logoRenderWidth / _logoRenderHeight;

  @override
  void initState() {
    super.initState();
    _render();
  }

  void _render() {
    final source = widget.source;
    final srcRatio = source.width / source.height;
    final targetRatio = _aspectRatio;

    // Base crop box: the largest box with the target aspect ratio that fits
    // inside the source image.
    int baseWidth;
    int baseHeight;
    if (srcRatio > targetRatio) {
      baseHeight = source.height;
      baseWidth = (baseHeight * targetRatio).round();
    } else {
      baseWidth = source.width;
      baseHeight = (baseWidth / targetRatio).round();
    }

    final cropWidth = (baseWidth / _zoom).round().clamp(1, source.width);
    final cropHeight = (baseHeight / _zoom).round().clamp(1, source.height);
    final maxX = source.width - cropWidth;
    final maxY = source.height - cropHeight;
    final x = ((maxX / 2) * (_horizontal + 1)).round().clamp(0, maxX);
    final y = ((maxY / 2) * (_vertical + 1)).round().clamp(0, maxY);
    final cropped = img.copyCrop(source,
        x: x, y: y, width: cropWidth, height: cropHeight);

    if (_isFavicon) {
      final full = img.copyResize(cropped,
          width: 256, height: 256, interpolation: img.Interpolation.cubic);
      final icon = img.Image.from(full);
      for (final size in const [64, 48, 32, 16]) {
        icon.addFrame(img.copyResize(full,
            width: size,
            height: size,
            interpolation: img.Interpolation.cubic));
      }
      _preview = img.encodePng(full);
      _ico = img.encodeIco(icon);
    } else {
      final full = img.copyResize(cropped,
          width: _logoRenderWidth * _logoPreviewScale,
          height: _logoRenderHeight * _logoPreviewScale,
          interpolation: img.Interpolation.cubic);
      _preview = img.encodePng(full);
      _ico = _preview;
    }
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _render();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_isFavicon
            ? 'Ajustar ícone dos Clients'
            : 'Ajustar logo dos Clients'),
        content: SizedBox(
          width: 620,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _isFavicon
                        ? Image.memory(_preview,
                            width: 256, height: 256, fit: BoxFit.cover)
                        : Image.memory(_preview,
                            width: _logoRenderWidth * 3.0,
                            height: _logoRenderHeight * 3.0,
                            fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isFavicon
                        ? 'A área quadrada acima será exatamente o ícone final.'
                        : 'A área acima segue a proporção real usada no Client (72×25).',
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Zoom ${_zoom.toStringAsFixed(1)}×'),
                    Slider(
                      value: _zoom,
                      min: 1,
                      max: 4,
                      divisions: 30,
                      onChanged: (value) => _change(() => _zoom = value),
                    ),
                    const Text('Posição horizontal'),
                    Slider(
                      value: _horizontal,
                      min: -1,
                      max: 1,
                      divisions: 40,
                      onChanged: (value) => _change(() => _horizontal = value),
                    ),
                    const Text('Posição vertical'),
                    Slider(
                      value: _vertical,
                      min: -1,
                      max: 1,
                      divisions: 40,
                      onChanged: (value) => _change(() => _vertical = value),
                    ),
                    const Divider(height: 28),
                    Text(_isFavicon ? 'Preview no Client' : 'Preview real no Client (72×25)'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xff091522),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _isFavicon
                          ? Row(children: [
                              Image.memory(_preview, width: 32, height: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(widget.brandName.trim().isEmpty
                                    ? 'Nome da marca'
                                    : widget.brandName.trim()),
                              ),
                              Image.memory(_preview, width: 16, height: 16),
                            ])
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.memory(_preview,
                                    width: _logoRenderWidth.toDouble(),
                                    height: _logoRenderHeight.toDouble(),
                                    fit: BoxFit.contain),
                              ],
                            ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isFavicon
                          ? 'O arquivo final contém 256, 64, 48, 32 e 16 pixels.'
                          : 'O arquivo final é salvo em alta resolução; no Client aparece em 72×25 pixels.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, _ImageCropResult(_ico, _preview)),
            icon: const Icon(Icons.check),
            label: Text(_isFavicon ? 'Usar este ícone' : 'Usar esta logo'),
          ),
        ],
      );
}
