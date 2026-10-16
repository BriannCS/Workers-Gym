// Hecho por Briann$ - Workers Corp.
// Control de personal y roles: las reglas del repositorio demo son las mismas
// que aplican RLS y los triggers en Supabase.
import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/data/demo_gym_repository.dart';
import 'package:gimnasio_app/domain/models.dart';
import 'package:gimnasio_app/domain/staff.dart';
import 'package:gimnasio_app/domain/workouts.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  setUpAll(initTestLocale);

  DemoGymRepository repoAs(StaffRole role) => DemoGymRepository.seeded(clock: () => testNow)..actAs(role);

  group('reglas por rol', () {
    test('recepción cobra pero no anula pagos ni ve al personal', () async {
      final repo = repoAs(StaffRole.reception);
      final payment = (await repo.payments()).firstWhere((p) => !p.voided);
      await expectLater(repo.voidPayment(payment.id, 'error'), throwsA(isA<GymException>()));
      await expectLater(repo.staffDirectory(), throwsA(isA<GymException>()));
      await expectLater(repo.setRolePermission(StaffRole.trainer, Perm.paymentsView, true), throwsA(isA<GymException>()));
      expect(await repo.members(), isNotEmpty);
    });

    test('el entrenador no ve pagos ni ventas y no crea clientes', () async {
      final repo = repoAs(StaffRole.trainer);
      expect(await repo.payments(), isEmpty);
      expect(await repo.sales(), isEmpty);
      expect((await repo.members()).where((m) => m.expiresOn != null), isNotEmpty, reason: 've los vencimientos');
      await expectLater(repo.createMember(const MemberInput(fullName: 'Nuevo Cliente')), throwsA(isA<GymException>()));
    });

    test('el administrador gestiona al personal pero no a los dueños', () async {
      final repo = repoAs(StaffRole.admin);
      await repo.setStaffStatus(DemoGymRepository.receptionId, StaffStatus.suspended);
      final laura = (await repo.staffDirectory()).firstWhere((s) => s.userId == DemoGymRepository.receptionId);
      expect(laura.status, StaffStatus.suspended);

      await expectLater(
        repo.updateStaff(DemoGymRepository.ownerId, const StaffInput(fullName: 'Briann', role: StaffRole.reception)),
        throwsA(isA<GymException>()),
      );
      await expectLater(
        repo.updateStaff(DemoGymRepository.trainerId, const StaffInput(fullName: 'Pedro Salazar', role: StaffRole.owner)),
        throwsA(isA<GymException>()),
      );
    });

    test('siempre queda un dueño activo y nadie se suspende a sí mismo', () async {
      final repo = repoAs(StaffRole.owner);
      await expectLater(
        repo.updateStaff(DemoGymRepository.ownerId, const StaffInput(fullName: 'Briann', role: StaffRole.admin)),
        throwsA(isA<GymException>().having((e) => e.message, 'mensaje', contains('dueño'))),
      );
      await expectLater(repo.setStaffStatus(DemoGymRepository.ownerId, StaffStatus.suspended), throwsA(isA<GymException>()));
    });

    test('una cuenta suspendida pierde el acceso', () async {
      final repo = repoAs(StaffRole.owner);
      await repo.setStaffStatus(DemoGymRepository.trainerId, StaffStatus.suspended);
      repo.actAs(StaffRole.trainer);
      expect(await repo.myAccess(), isNull);
      expect(await repo.members(), isEmpty);
    });

    test('el dueño cambia permisos y aplican al instante', () async {
      final repo = repoAs(StaffRole.owner);
      await repo.setRolePermission(StaffRole.trainer, Perm.paymentsView, true);
      repo.actAs(StaffRole.trainer);
      expect((await repo.myAccess())!.can(Perm.paymentsView), isTrue);
      expect(await repo.payments(), isNotEmpty);
    });

    test('marcar entrada y salida suma horas', () async {
      var now = DateTime(2026, 9, 28, 6, 12);
      final repo = DemoGymRepository.seeded(clock: () => now)..actAs(StaffRole.reception);
      final open = await repo.clockInOut();
      expect(open.open, isTrue);
      now = now.add(const Duration(hours: 8, minutes: 3));
      final closed = await repo.clockInOut();
      expect(closed.open, isFalse);
      expect(closed.worked(now), const Duration(hours: 8, minutes: 3));
      final shifts = await repo.shifts(DemoGymRepository.receptionId);
      expect(lateMinutes(closed, shifts), 12, reason: 'su turno empieza a las 06:00');
    });

    test('entrenos: el entrenador anota y solo edita lo suyo', () async {
      final repo = repoAs(StaffRole.trainer);
      final member = (await repo.members()).first;
      final id = await repo.saveWorkout(
        WorkoutInput(
          memberId: member.id,
          trainedOn: testNow,
          bodyParts: const [BodyPart.pecho, BodyPart.triceps],
          types: const [WorkoutType.hipertrofia],
          effort: 4,
        ),
      );
      final mine = (await repo.workouts(memberId: member.id)).firstWhere((w) => w.id == id);
      expect(mine.trainerName, 'Pedro Salazar');
      await expectLater(
        repo.saveWorkout(WorkoutInput(memberId: member.id, trainedOn: testNow)),
        throwsA(isA<GymException>()),
        reason: 'vacío',
      );

      repo.actAs(StaffRole.reception);
      expect(await repo.workouts(), isEmpty, reason: 'recepción no ve entrenos');
      await expectLater(repo.deleteWorkout(id), throwsA(isA<GymException>()));

      repo.actAs(StaffRole.admin);
      await repo.deleteWorkout(id);
      expect((await repo.workouts()).any((w) => w.id == id), isFalse);
    });

    test('recepción no ve costos ni compras', () async {
      final repo = repoAs(StaffRole.reception);
      expect((await repo.products()).every((p) => p.costCents == null), isTrue);
      expect(await repo.purchases(), isEmpty);
      repo.actAs(StaffRole.owner);
      expect((await repo.products()).every((p) => p.costCents != null), isTrue);
    });

    test('equilibrio: días desde que se trabajó cada parte', () {
      final today = DateTime(2026, 10, 16);
      WorkoutLog log(int daysAgo, List<BodyPart> parts) => WorkoutLog(
        id: '$daysAgo',
        memberId: 'm',
        trainedOn: today.subtract(Duration(days: daysAgo)),
        bodyParts: parts,
        createdBy: 'x',
        createdAt: today,
      );
      final since = daysSinceWorked([
        log(5, [BodyPart.pecho]),
        log(2, [BodyPart.pecho, BodyPart.espalda]),
        log(9, [BodyPart.cuerpoCompleto]),
      ], today);
      expect(since[BodyPart.pecho], 2);
      expect(since[BodyPart.espalda], 2);
      expect(since[BodyPart.pantorrillas], 9, reason: 'cuerpo completo cuenta para todo');
    });

    test('alta de personal con contraseña y cédula únicas', () async {
      final repo = repoAs(StaffRole.admin);
      final id = await repo.createStaff(
        const NewStaff(
          input: StaffInput(fullName: 'Ana Torres', role: StaffRole.trainer, documentId: 'V-30111222'),
          email: 'ana@workers.gym',
          password: 'segura123',
        ),
      );
      expect((await repo.staffDirectory()).any((s) => s.userId == id), isTrue);
      await expectLater(
        repo.createStaff(
          const NewStaff(
            input: StaffInput(fullName: 'Otra', role: StaffRole.trainer),
            email: 'ANA@workers.gym',
            password: 'segura123',
          ),
        ),
        throwsA(isA<GymException>()),
      );
      await expectLater(
        repo.createStaff(
          const NewStaff(
            input: StaffInput(fullName: 'Jefa', role: StaffRole.owner),
            email: 'jefa@workers.gym',
            password: 'segura123',
          ),
        ),
        throwsA(isA<GymException>()),
        reason: 'un administrador no crea dueños',
      );
    });
  });

  group('la app muestra solo lo que el rol permite', () {
    testWidgets('recepción: sin Personal, sin anular pagos y sin tasa en Ajustes', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.reception)));
      await tester.pumpAndSettle();
      expect(find.text('PERSONAL'), findsNothing);
      expect(find.text('PAGOS'), findsOneWidget);

      await goTo(tester, 'Pagos');
      expect(find.byTooltip('Anular pago'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Registrar pago'), findsOneWidget);

      await goTo(tester, 'Ajustes');
      expect(find.text('MI CUENTA'), findsOneWidget);
      expect(find.text('Ej. Pago móvil BDV, PayPal'), findsNothing);
    });

    testWidgets('entrenador: solo inicio, asistencia, clientes y ajustes', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.trainer)));
      await tester.pumpAndSettle();
      for (final visible in ['INICIO', 'ASISTENCIA', 'CLIENTES', 'ENTRENOS', 'AJUSTES']) {
        expect(find.text(visible), findsOneWidget, reason: visible);
      }
      for (final hidden in ['PAGOS', 'TIENDA', 'INVENTARIO', 'COMPRAS', 'CAJA', 'PLANES', 'PERSONAL']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.textContaining('INGRESOS'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Registrar pago'), findsNothing);
    });

    testWidgets('dueño: ve al equipo, da de alta y edita permisos', (tester) async {
      useDesktopWindow(tester);
      final repo = repoAs(StaffRole.owner);
      await tester.pumpWidget(buildTestApp(repo: repo));
      await tester.pumpAndSettle();
      await goTo(tester, 'Personal');
      expect(find.text('Briann'), findsWidgets, reason: 'en la lista y en su tarjeta');
      for (final name in ['Mariana López', 'Laura Rivas', 'Pedro Salazar']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Nueva persona'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo *'), 'Ana Torres');
      await tester.enterText(find.widgetWithText(TextFormField, 'Correo (para entrar) *'), 'ana@workers.gym');
      await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña inicial *'), 'segura123');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Torres'), findsOneWidget);

      await tester.tap(find.text('Roles y permisos'));
      await tester.pumpAndSettle();
      expect(find.text('Anular pagos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el botón de marcaje de la tarjeta registra la entrada', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.reception)));
      await tester.pumpAndSettle();
      expect(find.text('Laura Rivas'), findsOneWidget);
      expect(find.text('RECEPCIÓN'), findsOneWidget);
      await tester.tap(find.byTooltip('Marcar entrada'));
      await tester.pumpAndSettle();
      expect(find.text('RECEPCIÓN · EN TURNO 17:30'), findsOneWidget);
      expect(find.byTooltip('Marcar salida'), findsOneWidget);
    });

    testWidgets('recepción no ve ingresos, caja, compras ni costos', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.reception)));
      await tester.pumpAndSettle();
      for (final hidden in ['CAJA', 'COMPRAS', 'PERSONAL']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.textContaining('INGRESOS'), findsNothing);

      await goTo(tester, 'Pagos');
      expect(find.text('ESTE MES'), findsNothing);

      await goTo(tester, 'Inventario');
      expect(find.text('VALOR DEL INVENTARIO'), findsNothing);
      expect(find.text('COSTO'), findsNothing);
      expect(find.text('MARGEN'), findsNothing);
      expect(find.text('Proveedores'), findsNothing);
      expect(find.text('STOCK'), findsOneWidget);
    });

    testWidgets('el dueño sí ve costos e ingresos', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.owner)));
      await tester.pumpAndSettle();
      await goTo(tester, 'Inventario');
      expect(find.text('VALOR DEL INVENTARIO'), findsOneWidget);
      expect(find.text('MARGEN'), findsOneWidget);
    });

    testWidgets('el menú lateral se contrae y se vuelve a abrir', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.owner)));
      await tester.pumpAndSettle();
      expect(find.text('INVENTARIO'), findsOneWidget);
      await tester.tap(find.byTooltip('Contraer menú'));
      await tester.pumpAndSettle();
      expect(find.text('INVENTARIO'), findsNothing);
      expect(find.byTooltip('Abrir menú'), findsOneWidget);
      await tester.tap(find.byTooltip('Abrir menú'));
      await tester.pumpAndSettle();
      expect(find.text('INVENTARIO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el entrenador registra un entreno', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repoAs(StaffRole.trainer)));
      await tester.pumpAndSettle();
      await goTo(tester, 'Entrenos');
      expect(find.text('BITÁCORA'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar entreno').first);
      await tester.pumpAndSettle();
      // Sin cliente no guarda.
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Elige el cliente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
