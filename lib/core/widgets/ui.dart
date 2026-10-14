// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Página

/// Contenedor de cada sección: márgenes según el tamaño de pantalla, ancho
/// máximo de lectura y scroll.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final h = w < Breakpoints.phone ? 16.0 : (w < Breakpoints.desktop ? 28.0 : 44.0);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(h, w < Breakpoints.phone ? 20 : 36, h, 64),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 24), ...children]),
          ),
        ),
      ),
    );
  }
}

/// Encabezado tipo portada de sección: rótulo mono arriba, título de
/// marcador y una regla de tinta gruesa debajo.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null) ...[Text(subtitle!.toUpperCase(), style: AppText.label), const SizedBox(height: 6)],
        Text(title.toUpperCase(), style: AppText.score(phone ? 44 : 64)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone || actions.isEmpty)
          heading
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          ),
        const SizedBox(height: 14),
        const _InkRule(),
        if (phone && actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 10, runSpacing: 10, children: actions)],
      ],
    );
  }
}

/// Doble regla de tinta (gruesa + fina), como los formularios impresos.
class _InkRule extends StatelessWidget {
  const _InkRule();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(height: 3, color: AppColors.ink),
      const SizedBox(height: 2),
      Container(height: 1, color: AppColors.ink),
    ],
  );
}

// ---------------------------------------------------------------------------
// Hojas y marcadores

/// Hoja suelta con marco de tinta. El título va como rótulo de formulario,
/// subrayado por una línea de tinta.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, this.padding = const EdgeInsets.all(20), required this.child});

  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material (no DecoratedBox) para que el hover/ripple de las filas se vea.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppColors.ink, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              constraints: const BoxConstraints(minHeight: 48),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: AppText.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class Score {
  const Score({required this.label, required this.value, this.caption, this.color = AppColors.ink, this.onTap});

  final String label;
  final String value;
  final String? caption;
  final Color color;
  final VoidCallback? onTap;
}

/// Marcador: una sola tira enmarcada con columnas separadas por reglas,
/// como el tablero de un gimnasio. En teléfono pasa a 2 columnas.
class ScoreBoard extends StatelessWidget {
  const ScoreBoard({super.key, required this.scores});

  final List<Score> scores;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth < 520 ? 2 : scores.length;
        final rows = [for (var i = 0; i < scores.length; i += perRow) scores.sublist(i, (i + perRow).clamp(0, scores.length))];
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: const BorderSide(color: AppColors.ink, width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (r, row) in rows.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: r == 0 ? null : const Border(top: BorderSide(color: AppColors.ink, width: 1.2)),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, s) in row.indexed) ...[
                          if (i > 0) const VerticalDivider(width: 1.2, thickness: 1.2, color: AppColors.ink),
                          Expanded(
                            child: _ScoreCell(score: s, compact: perRow == 2),
                          ),
                        ],
                        // Completa la última fila para que las columnas no se estiren.
                        for (var k = row.length; k < perRow; k++) ...[
                          const VerticalDivider(width: 1.2, thickness: 1.2, color: AppColors.ink),
                          const Expanded(child: SizedBox()),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({required this.score, required this.compact});

  final Score score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = score;
    return InkWell(
      onTap: s.onTap,
      hoverColor: AppColors.raised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, color: s.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.label.toUpperCase(), style: AppText.label, overflow: TextOverflow.ellipsis),
                ),
                if (s.onTap != null) const Icon(Icons.north_east, size: 14, color: AppColors.textMuted),
              ],
            ),
            SizedBox(height: compact ? 8 : 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(s.value, style: AppText.score(compact ? 40 : 54, color: s.color == AppColors.ink ? AppColors.ink : s.color)),
            ),
            if (s.caption != null) ...[
              const SizedBox(height: 6),
              Text(s.caption!, style: AppText.muted.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

/// Distribuye elementos en columnas iguales según el ancho disponible.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 230, this.spacing = 16});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = ((c.maxWidth + spacing) / (minItemWidth + spacing)).floor().clamp(1, children.length.clamp(1, 99));
        final width = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Identidad de cliente

/// Estado de membresía como sello de tinta: marco, mayúsculas, levemente
/// torcido — lo que haría recepción con un sello de goma.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.large = false});

  final MembershipStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(status);
    return Transform.rotate(
      angle: -.035,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 7, vertical: large ? 4 : 2),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: large ? 2.2 : 1.6),
          borderRadius: BorderRadius.circular(2),
          color: color.withValues(alpha: .06),
        ),
        child: Text(
          status.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: large ? 20 : 13.5,
            letterSpacing: large ? 1.4 : 1,
            color: color,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Foto del cliente o, si no tiene, sus iniciales como placa de camiseta:
/// bloque de tinta con una franja inferior del color de su estado.
class Initials extends ConsumerWidget {
  const Initials(this.member, {super.key, this.size = 38, this.status});

  final Member member;
  final double size;
  final MembershipStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = member.photoPath == null ? null : ref.watch(memberPhotosProvider).value;
    final photo = photos?[member.id];
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(2),
          image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
          border: status == null
              ? null
              : Border(
                  bottom: BorderSide(color: AppColors.forStatus(status!), width: size * .12),
                ),
        ),
        child: photo != null
            ? null
            : Center(
                child: Text(
                  member.initials,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: size * .46,
                    color: AppColors.surface,
                    letterSpacing: .5,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados vacíos, carga y tablas

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.borderStrong),
          const SizedBox(height: 12),
          Text(
            title.toUpperCase(),
            style: AppText.score(22, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[const SizedBox(height: 6), Text(message!, style: AppText.muted, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Muestra carga / error con reintento / datos para un [AsyncValue].
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.data, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (value) {
      AsyncValue(:final value?, hasValue: true) => data(value),
      AsyncError(:final error) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los datos',
        message: '$error',
        action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
      ),
      _ => const Padding(padding: EdgeInsets.all(40), child: LinearProgressIndicator(minHeight: 2)),
    };
  }
}

/// Encabezado de columnas: rótulos mono sobre una regla de tinta.
class TableHeader extends StatelessWidget {
  const TableHeader({super.key, required this.cells});

  final List<(String, int)> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2)),
      ),
      child: Row(
        children: [
          for (final (label, flex) in cells)
            Expanded(
              flex: flex,
              child: Text(label.toUpperCase(), style: AppText.label, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// Línea de fila de cuaderno (separador estándar entre filas).
const rowRule = Border(bottom: BorderSide(color: AppColors.border));

/// Línea perforada de ticket.
class Perforation extends StatelessWidget {
  const Perforation({super.key, this.color = AppColors.borderStrong});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: double.infinity,
    child: CustomPaint(painter: _DashPainter(color)),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset((x + 3.5).clamp(0, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Renglón de ticket: concepto, puntos guía y monto alineado a la derecha.
class LeaderLine extends StatelessWidget {
  const LeaderLine(this.label, this.value, {super.key, this.strong = false, this.color});

  final String label;
  final String value;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = AppText.mono(size: strong ? 14 : 13, weight: strong ? FontWeight.w600 : FontWeight.w400, color: color ?? AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(builder: (context, c) {
        // Se mide el monto primero: siempre se ve entero y alineado a la
        // derecha; el concepto usa lo que sobra (y se recorta si no cabe).
        final valueWidth = (TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout())
            .width;
        final labelMax = (c.maxWidth - valueWidth - 24).clamp(0.0, double.infinity);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: labelMax),
              child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            const Expanded(child: Padding(padding: EdgeInsets.only(bottom: 4), child: _Dots())),
            const SizedBox(width: 6),
            Flexible(flex: 0, child: Text(value, style: style, maxLines: 1, overflow: TextOverflow.clip)),
          ],
        );
      }),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => SizedBox(height: 1.5, child: CustomPaint(painter: _DotsPainter()));
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.borderStrong;
    for (double x = 0; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x + 1, .75), .75, p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

/// Nota adhesiva pegada a la página: para avisos que recepción debe ver
/// (stock bajo, pendientes). Amarillo de disco de 15 kg.
class StickyNote extends StatelessWidget {
  const StickyNote({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .008,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.plateYellow,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: .18), offset: const Offset(2, 3), blurRadius: 0)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title.toUpperCase(), style: AppText.score(22))),
                ?trailing,
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avisos y diálogos

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(width: 4, height: 28, color: error ? AppColors.plateRed : AppColors.plateGreen),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Estructura común de los formularios. En escritorio es un diálogo con marco
/// de tinta; en teléfono ocupa toda la pantalla con los botones abajo.
class FormDialog extends StatelessWidget {
  const FormDialog({super.key, required this.title, this.subtitle, required this.child, required this.actions, this.width = 520});

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 24, phone ? 12 : 20, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle!.toUpperCase(), style: AppText.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                ],
                Text(title.toUpperCase(), style: AppText.score(phone ? 30 : 34)),
              ],
            ),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), tooltip: 'Cerrar'),
        ],
      ),
    );
    final body = Padding(padding: EdgeInsets.fromLTRB(phone ? 16 : 24, 16, phone ? 16 : 24, 8), child: child);
    final buttons = Container(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 24, 14, phone ? 16 : 24, phone ? 16 : 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: phone
          ? Row(spacing: 10, children: [for (final a in actions) Expanded(child: a)])
          : Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: actions),
    );

    if (phone) {
      return Dialog.fullscreen(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              Container(height: 3, color: AppColors.ink),
              Expanded(child: SingleChildScrollView(child: body)),
              buttons,
            ],
          ),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Container(height: 3, color: AppColors.ink),
            ),
            Flexible(child: SingleChildScrollView(child: body)),
            buttons,
          ],
        ),
      ),
    );
  }
}

/// Pide el motivo de una anulación. Devuelve null si se cancela.
Future<String?> askVoidReason(BuildContext context, {required String title, required String detail}) => showDialog<String>(
  context: context,
  builder: (_) => _VoidReasonDialog(title: title, detail: detail),
);

class _VoidReasonDialog extends StatefulWidget {
  const _VoidReasonDialog({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  State<_VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<_VoidReasonDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.title,
      subtitle: widget.detail,
      width: 460,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
          onPressed: _submit,
          child: const Text('Anular'),
        ),
      ],
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _reason,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ej. cobrado dos veces'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'El motivo es obligatorio' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    );
  }
}
