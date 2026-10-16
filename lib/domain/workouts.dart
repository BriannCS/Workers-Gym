// Hecho por Briann$ - Workers Corp.
// Entrenos: lo que un entrenador anota de cada sesión de un cliente. Los
// códigos son los mismos que aceptan las restricciones de `workout_logs`.
import 'models.dart' show isoDate;

/// Zona del cuerpo trabajada. [group] agrupa en el formulario y el mapa.
enum BodyPart {
  pecho('pecho', 'Pecho', BodyZone.upper),
  espalda('espalda', 'Espalda', BodyZone.upper),
  hombros('hombros', 'Hombros', BodyZone.upper),
  biceps('biceps', 'Bíceps', BodyZone.upper),
  triceps('triceps', 'Tríceps', BodyZone.upper),
  antebrazos('antebrazos', 'Antebrazos', BodyZone.upper),
  abdomen('abdomen', 'Abdomen', BodyZone.core),
  lumbar('lumbar', 'Lumbar', BodyZone.core),
  gluteos('gluteos', 'Glúteos', BodyZone.lower),
  cuadriceps('cuadriceps', 'Cuádriceps', BodyZone.lower),
  isquios('isquios', 'Isquiotibiales', BodyZone.lower),
  aductores('aductores', 'Aductores', BodyZone.lower),
  pantorrillas('pantorrillas', 'Pantorrillas', BodyZone.lower),
  cuerpoCompleto('cuerpo_completo', 'Cuerpo completo', BodyZone.full);

  const BodyPart(this.code, this.label, this.zone);
  final String code;
  final String label;
  final BodyZone zone;

  static BodyPart? fromCode(String code) => values.where((p) => p.code == code).firstOrNull;

  /// Partes concretas (sin "cuerpo completo"), para el mapa de equilibrio.
  static List<BodyPart> get specific => values.where((p) => p != cuerpoCompleto).toList();
}

enum BodyZone {
  upper('Tren superior'),
  core('Core'),
  lower('Tren inferior'),
  full('General');

  const BodyZone(this.label);
  final String label;
}

enum WorkoutType {
  fuerza('fuerza', 'Fuerza'),
  hipertrofia('hipertrofia', 'Hipertrofia'),
  resistencia('resistencia', 'Resistencia'),
  cardio('cardio', 'Cardio'),
  hiit('hiit', 'HIIT'),
  funcional('funcional', 'Funcional'),
  movilidad('movilidad', 'Movilidad'),
  tecnica('tecnica', 'Técnica'),
  rehabilitacion('rehabilitacion', 'Rehabilitación'),
  evaluacion('evaluacion', 'Evaluación');

  const WorkoutType(this.code, this.label);
  final String code;
  final String label;

  static WorkoutType? fromCode(String code) => values.where((t) => t.code == code).firstOrNull;
}

/// Esfuerzo percibido, 1 a 5.
const effortLabels = ['Suave', 'Moderado', 'Exigente', 'Duro', 'Al límite'];

class WorkoutLog {
  const WorkoutLog({
    required this.id,
    required this.memberId,
    required this.trainedOn,
    required this.createdBy,
    required this.createdAt,
    this.memberName,
    this.bodyParts = const [],
    this.types = const [],
    this.durationMin,
    this.effort,
    this.notes,
    this.trainerName = '',
  });

  final String id;
  final String memberId;
  final String? memberName;
  final DateTime trainedOn;
  final List<BodyPart> bodyParts;
  final List<WorkoutType> types;
  final int? durationMin;
  final int? effort;
  final String? notes;
  final String createdBy;
  final String trainerName;
  final DateTime createdAt;

  /// Partes concretas trabajadas: "cuerpo completo" cuenta como todas.
  Set<BodyPart> get worked => bodyParts.contains(BodyPart.cuerpoCompleto) ? BodyPart.specific.toSet() : bodyParts.toSet();

  factory WorkoutLog.fromJson(Map<String, dynamic> j) => WorkoutLog(
    id: j['id'] as String,
    memberId: j['member_id'] as String,
    memberName: (j['members'] as Map?)?['full_name'] as String?,
    trainedOn: DateTime.parse(j['trained_on'] as String),
    bodyParts: [for (final c in (j['body_parts'] as List? ?? const [])) ?BodyPart.fromCode(c as String)],
    types: [for (final c in (j['workout_types'] as List? ?? const [])) ?WorkoutType.fromCode(c as String)],
    durationMin: j['duration_min'] as int?,
    effort: j['effort'] as int?,
    notes: j['notes'] as String?,
    createdBy: j['created_by'] as String,
    trainerName: j['trainer_name'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

class WorkoutInput {
  const WorkoutInput({
    required this.memberId,
    required this.trainedOn,
    this.bodyParts = const [],
    this.types = const [],
    this.durationMin,
    this.effort,
    this.notes,
  });

  final String memberId;
  final DateTime trainedOn;
  final List<BodyPart> bodyParts;
  final List<WorkoutType> types;
  final int? durationMin;
  final int? effort;
  final String? notes;

  bool get hasContent => bodyParts.isNotEmpty || types.isNotEmpty || (notes ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'member_id': memberId,
    'trained_on': isoDate(trainedOn),
    'body_parts': [for (final p in bodyParts) p.code],
    'workout_types': [for (final t in types) t.code],
    'duration_min': durationMin,
    'effort': effort,
    'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
  };
}

/// Días desde la última vez que se trabajó cada parte (null = nunca en el
/// historial dado).
Map<BodyPart, int?> daysSinceWorked(Iterable<WorkoutLog> logs, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final last = <BodyPart, DateTime>{};
  for (final l in logs) {
    for (final p in l.worked) {
      final prev = last[p];
      if (prev == null || l.trainedOn.isAfter(prev)) last[p] = l.trainedOn;
    }
  }
  return {
    for (final p in BodyPart.specific)
      p: last[p] == null ? null : day.difference(DateTime(last[p]!.year, last[p]!.month, last[p]!.day)).inDays,
  };
}
