// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../data/gym_repository.dart';
import '../../data/sync.dart';
import '../env.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode.dart';
import 'brand_mark.dart';
import 'staff_controls.dart';
import 'ui.dart';

/// Estructura principal. Escritorio: lomo de tinta con pestañas numeradas.
/// Tableta: el mismo lomo compacto. Teléfono: barra superior + barra inferior.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Una cuenta que inició sesión pero no está en `staff` no ve datos (RLS):
    // mejor decírselo que mostrar pantallas vacías.
    final staff = ref.watch(currentStaffProvider);
    if (staff case AsyncData(value: null)) return _NoAccess(supabase: ref.watch(supabaseClientProvider));

    // Sección fuera del rol (p. ej. entrando por URL): el servidor tampoco le
    // daría datos, así que se explica en vez de mostrar una pantalla vacía.
    final section = AppSection.at(location);
    final allowed = staff.value == null || section == null || section.allowedFor(staff.value);

    final sync = ref.watch(syncStatusProvider);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sync == SyncStatus.offline) const _OfflineBanner(),
        Expanded(child: _Paper(child: allowed ? child : const NotAllowed())),
      ],
    );

    if (context.isPhone) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhoneTopBar(sync: sync),
              Expanded(child: content),
            ],
          ),
        ),
        bottomNavigationBar: _PhoneTabBar(location: location),
      );
    }
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Spine(location: location, compact: !context.isDesktop, sync: sync),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Fondo de página: papel con una retícula de puntos muy tenue (hoja de
/// cuaderno de entrenamiento).
class _Paper extends StatelessWidget {
  const _Paper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _DotGridPainter())),
          child,
        ],
      );
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);
    final dot = Paint()..color = AppColors.border.withValues(alpha: .7);
    const step = 24.0;
    for (double y = step; y < size.height; y += step) {
      for (double x = step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), .9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.plateYellow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18, color: AppColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión. Ves los últimos datos cargados; cobros y ventas vuelven al reconectar.',
              style: AppText.mono(size: 12.5, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indicador de sincronización

class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key, required this.status, this.onDark = false, this.showLabel = true});

  final SyncStatus status;
  final bool onDark;
  final bool showLabel;

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SyncIndicator old) {
    super.didUpdateWidget(old);
    _sync();
  }

  // Solo late mientras está en vivo: sin animaciones inútiles.
  void _sync() => widget.status == SyncStatus.live ? _pulse.repeat() : _pulse.stop();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.status) {
      SyncStatus.live => const Color(0xFF3FBF63),
      SyncStatus.connecting => AppColors.plateYellow,
      SyncStatus.offline => AppColors.plateRed,
      SyncStatus.local => AppColors.borderStrong,
    };
    final dot = SizedBox.square(
      dimension: 14,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.status == SyncStatus.live)
              Container(
                width: 6 + 8 * _pulse.value,
                height: 6 + 8 * _pulse.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .45 * (1 - _pulse.value))),
              ),
            Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          ],
        ),
      ),
    );
    return Tooltip(
      message: switch (widget.status) {
        SyncStatus.live => 'Sincronizado en tiempo real con los demás dispositivos',
        SyncStatus.connecting => 'Conectando con el servidor…',
        SyncStatus.offline => 'Sin conexión: los cambios de otros dispositivos llegarán al reconectar',
        SyncStatus.local => 'Datos de prueba solo en este dispositivo',
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          if (widget.showLabel) ...[
            const SizedBox(width: 6),
            Text(
              widget.status.label.toUpperCase(),
              style: AppText.label.copyWith(color: widget.onDark ? AppColors.onSpine.withValues(alpha: .75) : AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Escritorio / tableta: lomo de tinta

class _Spine extends ConsumerWidget {
  const _Spine({required this.location, required this.compact, required this.sync});

  final String location;
  final bool compact;
  final SyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseClientProvider);
    final access = ref.watch(currentStaffProvider).value;
    final staffName = access?.fullName;
    final paperDim = AppColors.onSpine.withValues(alpha: .6);
    return Container(
      width: compact ? 88 : 244,
      color: AppColors.spine,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 0 : 22, 24, 0, 28),
              child: compact
                  ? const Center(child: BrandMark(size: 44))
                  : Row(
                      children: [
                        const BrandMark(size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Env.gymName.toUpperCase(),
                                  overflow: TextOverflow.ellipsis, style: AppText.score(26, color: AppColors.onSpine)),
                              Text('WORKERS RECEPCIÓN', style: AppText.label.copyWith(color: paperDim, fontSize: 9.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in AppSection.values.where((s) => s.allowedFor(access)))
                      _SpineTab(section: s, selected: s.path == location, compact: compact),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 0 : 22, 12, compact ? 0 : 16, 20),
              child: Column(
                crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  if (compact) ...[
                    const ClockButton(onSpine: true, compact: true),
                    const ThemeToggle(onSpine: true),
                    const SizedBox(height: 8),
                    SyncIndicator(status: sync, onDark: true, showLabel: false),
                  ] else ...[
                    const ClockButton(onSpine: true),
                    const SizedBox(height: 10),
                    const DemoRoleSwitcher(onSpine: true),
                    Row(
                      children: [
                        Expanded(child: SyncIndicator(status: sync, onDark: true)),
                        const ThemeToggle(onSpine: true),
                      ],
                    ),
                  ],
                  if (supabase != null) ...[
                    const SizedBox(height: 14),
                    _SignOut(
                      compact: compact,
                      name: staffName ?? supabase.auth.currentUser?.email ?? 'Recepción',
                      onTap: () => supabase.auth.signOut(),
                    ),
                  ],
                  if (!compact) ...[
                    const SizedBox(height: 16),
                    BrandSignature(color: paperDim, size: 9),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña de cuaderno: la activa toma el color del papel y se funde con la
/// página, como un separador asomando del borde.
class _SpineTab extends StatelessWidget {
  const _SpineTab({required this.section, required this.selected, required this.compact});

  final AppSection section;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final number = (section.index + 1).toString().padLeft(2, '0');
    final fg = selected ? AppColors.ink : AppColors.onSpine.withValues(alpha: .78);
    final tab = Padding(
      padding: EdgeInsets.only(left: compact ? 10 : 14, bottom: 2),
      child: Material(
        color: selected ? AppColors.bg : Colors.transparent,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppTheme.radius)),
        child: InkWell(
          onTap: () => context.go(section.path),
          hoverColor: Colors.white.withValues(alpha: .06),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppTheme.radius)),
          child: SizedBox(
            height: compact ? 58 : 46,
            child: compact
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(section.icon, size: 20, color: fg),
                      const SizedBox(height: 3),
                      Text(number, style: AppText.mono(size: 10, color: selected ? AppColors.plateBlue : fg)),
                    ],
                  )
                : Row(
                    children: [
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 26,
                        child: Text(number, style: AppText.mono(size: 11.5, color: selected ? AppColors.plateBlue : fg.withValues(alpha: .55))),
                      ),
                      Expanded(
                        child: Text(
                          section.label.toUpperCase(),
                          style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 21,
                            letterSpacing: .6,
                            color: fg,
                          ),
                        ),
                      ),
                      if (selected) Container(width: 4, height: 22, color: AppColors.plateBlue, margin: const EdgeInsets.only(right: 14)),
                    ],
                  ),
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: section.label, waitDuration: const Duration(milliseconds: 300), child: tab) : tab;
  }
}

class _SignOut extends StatelessWidget {
  const _SignOut({required this.compact, required this.name, required this.onTap});

  final bool compact;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = AppColors.onSpine.withValues(alpha: .6);
    if (compact) {
      return IconButton(
        tooltip: '$name · Cerrar sesión',
        onPressed: onTap,
        icon: Icon(Icons.logout, color: dim, size: 20),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.onSpine, fontWeight: FontWeight.w600, fontSize: 13)),
                Text('CERRAR SESIÓN', style: AppText.label.copyWith(color: dim, fontSize: 10)),
              ],
            ),
          ),
          Icon(Icons.logout, color: dim, size: 18),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teléfono

class _PhoneTopBar extends StatelessWidget {
  const _PhoneTopBar({required this.sync});

  final SyncStatus sync;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2)),
      ),
      child: Row(
        children: [
          const BrandMark(size: 34),
          const SizedBox(width: 10),
          Expanded(child: Text(Env.gymName.toUpperCase(), style: AppText.score(24), overflow: TextOverflow.ellipsis)),
          SyncIndicator(status: sync),
          const ThemeToggle(),
        ],
      ),
    );
  }
}

class _PhoneTabBar extends ConsumerWidget {
  const _PhoneTabBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(currentStaffProvider).value;
    final current = AppSection.at(location);
    final bar = AppSection.values.where((s) => s.onPhoneBar && s.allowedFor(access)).toList();
    final moreSelected = current != null && !bar.contains(current);
    Widget item({required IconData icon, required String label, required bool selected, required VoidCallback onTap}) {
      final fg = selected ? AppColors.onSpine : AppColors.onSpine.withValues(alpha: .6);
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 22, height: 3, color: selected ? AppColors.plateBlue : Colors.transparent),
              const SizedBox(height: 7),
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 3),
              Text(label.toUpperCase(), style: AppText.label.copyWith(fontSize: 9.5, color: fg, letterSpacing: .8)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppColors.spine,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final s in bar)
                item(icon: s.icon, label: s.label, selected: s == current, onTap: () => context.go(s.path)),
              item(
                icon: Icons.more_horiz,
                label: moreSelected ? current.label : 'Más',
                selected: moreSelected,
                onTap: () => showModalBottomSheet<void>(context: context, builder: (_) => _MoreSheet(location: location)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheet extends ConsumerWidget {
  const _MoreSheet({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supabase = ref.watch(supabaseClientProvider);
    final access = ref.watch(currentStaffProvider).value;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 8), child: ClockButton()),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: DemoRoleSwitcher()),
            for (final s in AppSection.values.where((s) => !s.onPhoneBar && s.allowedFor(access)))
              ListTile(
                leading: Icon(s.icon, color: AppColors.ink),
                title: Text(s.label.toUpperCase(), style: AppText.score(24)),
                trailing: Text((s.index + 1).toString().padLeft(2, '0'), style: AppText.mono(color: AppColors.textMuted)),
                selected: s.path == location,
                selectedTileColor: AppColors.raised,
                shape: const Border(bottom: BorderSide(color: AppColors.border)),
                onTap: () {
                  Navigator.pop(context);
                  context.go(s.path);
                },
              ),
            if (supabase != null)
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: Text('CERRAR SESIÓN', style: AppText.score(22, color: AppColors.danger)),
                subtitle: Text(access?.fullName ?? supabase.auth.currentUser?.email ?? ''),
                onTap: () {
                  Navigator.pop(context);
                  supabase.auth.signOut();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.supabase});

  final SupabaseClient? supabase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EmptyState(
            icon: Icons.lock_outline,
            title: 'Tu cuenta no tiene acceso',
            message: '${supabase?.auth.currentUser?.email ?? 'Esta cuenta'} no está registrada como personal del gimnasio. '
                'Pide al administrador que te agregue.',
            action: OutlinedButton(onPressed: () => supabase?.auth.signOut(), child: const Text('Cerrar sesión')),
          ),
        ),
      ),
    );
  }
}

/// Cambia entre modo claro y oscuro con un clic. La preferencia es de cada
/// dispositivo y se recuerda.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key, this.onSpine = false});

  final bool onSpine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeModeProvider);
    return IconButton(
      tooltip: dark ? 'Modo claro' : 'Modo oscuro',
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 20,
        color: onSpine ? AppColors.onSpine.withValues(alpha: .8) : AppColors.ink,
      ),
    );
  }
}
