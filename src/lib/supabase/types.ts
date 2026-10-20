/**
 * Datenbank-Typen (manuell gepflegt, entspricht supabase/migrations/*.sql).
 * Bei Schemaänderungen hier mitziehen.
 */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type MuscleRole = "primary" | "secondary";
export type EquipmentType =
  | "machine"
  | "cable"
  | "barbell"
  | "dumbbell"
  | "bodyweight"
  | "smith_machine"
  | "bench"
  | "other"
  | "cardio";
export type ExerciseCategory =
  | "chest"
  | "back"
  | "shoulders"
  | "biceps"
  | "triceps"
  | "quads"
  | "hamstrings"
  | "glutes"
  | "calves"
  | "abs"
  | "forearms"
  | "adductors"
  | "cardio";
export type SessionStatus = "active" | "completed" | "cancelled";
export type CalendarEntryType = "training" | "rest" | "leisure" | "party" | "other";
export type WeightUnit = "kg" | "lb";
export type ThemePreference = "dark" | "light" | "system";
export type UserRole = "user" | "admin";

export type MuscleId =
  | "chest"
  | "upper_chest"
  | "front_delts"
  | "side_delts"
  | "rear_delts"
  | "traps"
  | "lats"
  | "upper_back"
  | "mid_back"
  | "lower_back"
  | "biceps"
  | "triceps"
  | "forearms"
  | "abs"
  | "obliques"
  | "quads"
  | "hamstrings"
  | "glutes"
  | "calves"
  | "adductors"
  | "abductors";

export type CableSetup = {
  cable: string;
  height: string;
  seat_position?: string;
  grip_width: string;
  body_position: string;
  foot_position: string;
  movement_direction: string;
  elbow_position: string;
  end_position: string;
  return: string;
};

type Timestamps = { created_at: string; updated_at: string };

export type ProfileRow = Timestamps & {
  id: string;
  nickname: string;
  role: UserRole;
};

export type UserSettingsRow = Timestamps & {
  user_id: string;
  weight_unit: WeightUnit;
  weight_step: number;
  rest_timer_default: number;
  show_rir: boolean;
  theme: ThemePreference;
};

export type MuscleGroupRow = {
  id: string;
  name_de: string;
  region: "front" | "back" | "both";
  sort_order: number;
};

export type GripRow = {
  id: string;
  name_de: string;
  description: string;
  sort_order: number;
  image_url: string | null;
};

export type ExerciseRow = Timestamps & {
  id: string;
  slug: string;
  name: string;
  category: ExerciseCategory;
  equipment: EquipmentType;
  grip_id: string | null;
  grip_notes: string | null;
  description: string | null;
  setup: string[];
  execution: string[];
  range_of_motion: string | null;
  breathing: string | null;
  common_mistakes: string[];
  tips: string[];
  cable_setup: Json | null;
  image_url: string | null;
  animation_url: string | null;
  muscle_focus: string[];
  requirements: string[];
  grip_alternatives: string[];
  machine_name: string | null;
  alternative_exercises: string[];
  is_custom: boolean;
  owner_id: string | null;
};

export type ExerciseMuscleRow = {
  exercise_id: string;
  muscle_id: string;
  role: MuscleRole;
};

export type WorkoutPlanTemplateRow = Timestamps & {
  id: string;
  name: string;
  sort_order: number;
  is_active: boolean;
};

export type WorkoutPlanTemplateExerciseRow = {
  id: string;
  template_id: string;
  exercise_id: string;
  sort_order: number;
  target_sets: number;
  rep_min: number;
  rep_max: number;
};

export type WorkoutPlanRow = Timestamps & {
  id: string;
  user_id: string;
  template_id: string | null;
  name: string;
  sort_order: number;
  is_archived: boolean;
};

export type WorkoutPlanExerciseRow = Timestamps & {
  id: string;
  plan_id: string;
  exercise_id: string;
  sort_order: number;
  target_sets: number;
  rep_min: number;
  rep_max: number;
  notes: string | null;
};

export type WorkoutSessionRow = Timestamps & {
  id: string;
  user_id: string;
  plan_id: string | null;
  name: string;
  status: SessionStatus;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  total_volume: number;
  total_sets: number;
  notes: string | null;
};

export type WorkoutSessionExerciseRow = {
  id: string;
  session_id: string;
  user_id: string;
  exercise_id: string;
  sort_order: number;
  target_sets: number;
  rep_min: number;
  rep_max: number;
  created_at: string;
};

export type WorkoutSetRow = Timestamps & {
  id: string;
  session_exercise_id: string;
  user_id: string;
  set_number: number;
  weight: number;
  reps: number;
  rir: number | null;
  is_warmup: boolean;
  completed: boolean;
  completed_at: string;
};

export type CalendarEntryRow = Timestamps & {
  id: string;
  user_id: string;
  entry_date: string;
  entry_type: CalendarEntryType;
  note: string | null;
};

export type FavoriteRow = {
  user_id: string;
  exercise_id: string;
  created_at: string;
};

export type QuoteRow = {
  id: string;
  text: string;
  author: string | null;
  active: boolean;
  created_at: string;
};

export type BodyWeightEntryRow = {
  id: string;
  user_id: string;
  entry_date: string;
  weight: number;
  created_at: string;
};

type Insertable<Row, Optional extends keyof Row = never> = Omit<Row, Optional> & Partial<Pick<Row, Optional>>;

type Rel = {
  foreignKeyName: string;
  columns: string[];
  isOneToOne: boolean;
  referencedRelation: string;
  referencedColumns: string[];
};

type TableDef<Row, Insert, Rels extends Rel[] = [], Update = Partial<Insert>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: Rels;
};


export type Database = {
  public: {
    Tables: {
      profiles: TableDef<ProfileRow, Insertable<ProfileRow, "role" | "created_at" | "updated_at">>;
      user_settings: TableDef<
        UserSettingsRow,
        Insertable<
          UserSettingsRow,
          "weight_unit" | "weight_step" | "rest_timer_default" | "show_rir" | "theme" | "created_at" | "updated_at"
        >
      ,
        [
          { foreignKeyName: "user_settings_user_id_fkey", columns: ["user_id"], isOneToOne: true, referencedRelation: "profiles", referencedColumns: ["id"] }
        ]
      >;
      muscle_groups: TableDef<MuscleGroupRow, Insertable<MuscleGroupRow, "sort_order">>;
      grips: TableDef<GripRow, Insertable<GripRow, "sort_order" | "image_url">>;
      exercises: TableDef<
        ExerciseRow,
        Insertable<
          ExerciseRow,
          | "id"
          | "grip_id"
          | "grip_notes"
          | "description"
          | "setup"
          | "execution"
          | "range_of_motion"
          | "breathing"
          | "common_mistakes"
          | "tips"
          | "cable_setup"
          | "image_url"
          | "animation_url"
          | "muscle_focus"
          | "requirements"
          | "grip_alternatives"
          | "machine_name"
          | "alternative_exercises"
          | "is_custom"
          | "owner_id"
          | "created_at"
          | "updated_at"
        >
      ,
        [
          { foreignKeyName: "exercises_grip_id_fkey", columns: ["grip_id"], isOneToOne: false, referencedRelation: "grips", referencedColumns: ["id"] },
          { foreignKeyName: "exercises_owner_id_fkey", columns: ["owner_id"], isOneToOne: false, referencedRelation: "profiles", referencedColumns: ["id"] }
        ]
      >;
      exercise_muscles: TableDef<ExerciseMuscleRow, ExerciseMuscleRow,
        [
          { foreignKeyName: "exercise_muscles_exercise_id_fkey", columns: ["exercise_id"], isOneToOne: false, referencedRelation: "exercises", referencedColumns: ["id"] },
          { foreignKeyName: "exercise_muscles_muscle_id_fkey", columns: ["muscle_id"], isOneToOne: false, referencedRelation: "muscle_groups", referencedColumns: ["id"] }
        ]
      >;
      workout_plan_templates: TableDef<
        WorkoutPlanTemplateRow,
        Insertable<WorkoutPlanTemplateRow, "id" | "sort_order" | "is_active" | "created_at" | "updated_at">
      >;
      workout_plan_template_exercises: TableDef<
        WorkoutPlanTemplateExerciseRow,
        Insertable<WorkoutPlanTemplateExerciseRow, "id" | "sort_order" | "target_sets" | "rep_min" | "rep_max">
      ,
        [
          { foreignKeyName: "workout_plan_template_exercises_template_id_fkey", columns: ["template_id"], isOneToOne: false, referencedRelation: "workout_plan_templates", referencedColumns: ["id"] },
          { foreignKeyName: "workout_plan_template_exercises_exercise_id_fkey", columns: ["exercise_id"], isOneToOne: false, referencedRelation: "exercises", referencedColumns: ["id"] }
        ]
      >;
      workout_plans: TableDef<
        WorkoutPlanRow,
        Insertable<WorkoutPlanRow, "id" | "template_id" | "sort_order" | "is_archived" | "created_at" | "updated_at">
      ,
        [
          { foreignKeyName: "workout_plans_user_id_fkey", columns: ["user_id"], isOneToOne: false, referencedRelation: "profiles", referencedColumns: ["id"] },
          { foreignKeyName: "workout_plans_template_id_fkey", columns: ["template_id"], isOneToOne: false, referencedRelation: "workout_plan_templates", referencedColumns: ["id"] }
        ]
      >;
      workout_plan_exercises: TableDef<
        WorkoutPlanExerciseRow,
        Insertable<
          WorkoutPlanExerciseRow,
          "id" | "sort_order" | "target_sets" | "rep_min" | "rep_max" | "notes" | "created_at" | "updated_at"
        >
      ,
        [
          { foreignKeyName: "workout_plan_exercises_plan_id_fkey", columns: ["plan_id"], isOneToOne: false, referencedRelation: "workout_plans", referencedColumns: ["id"] },
          { foreignKeyName: "workout_plan_exercises_exercise_id_fkey", columns: ["exercise_id"], isOneToOne: false, referencedRelation: "exercises", referencedColumns: ["id"] }
        ]
      >;
      workout_sessions: TableDef<
        WorkoutSessionRow,
        Insertable<
          WorkoutSessionRow,
          | "id"
          | "plan_id"
          | "status"
          | "started_at"
          | "ended_at"
          | "duration_seconds"
          | "total_volume"
          | "total_sets"
          | "notes"
          | "created_at"
          | "updated_at"
        >
      ,
        [
          { foreignKeyName: "workout_sessions_user_id_fkey", columns: ["user_id"], isOneToOne: false, referencedRelation: "profiles", referencedColumns: ["id"] },
          { foreignKeyName: "workout_sessions_plan_id_fkey", columns: ["plan_id"], isOneToOne: false, referencedRelation: "workout_plans", referencedColumns: ["id"] }
        ]
      >;
      workout_session_exercises: TableDef<
        WorkoutSessionExerciseRow,
        Insertable<WorkoutSessionExerciseRow, "id" | "sort_order" | "target_sets" | "rep_min" | "rep_max" | "created_at">
      ,
        [
          { foreignKeyName: "workout_session_exercises_session_id_fkey", columns: ["session_id"], isOneToOne: false, referencedRelation: "workout_sessions", referencedColumns: ["id"] },
          { foreignKeyName: "workout_session_exercises_exercise_id_fkey", columns: ["exercise_id"], isOneToOne: false, referencedRelation: "exercises", referencedColumns: ["id"] }
        ]
      >;
      workout_sets: TableDef<
        WorkoutSetRow,
        Insertable<
          WorkoutSetRow,
          "id" | "weight" | "reps" | "rir" | "is_warmup" | "completed" | "completed_at" | "created_at" | "updated_at"
        >
      ,
        [
          { foreignKeyName: "workout_sets_session_exercise_id_fkey", columns: ["session_exercise_id"], isOneToOne: false, referencedRelation: "workout_session_exercises", referencedColumns: ["id"] }
        ]
      >;
      calendar_entries: TableDef<
        CalendarEntryRow,
        Insertable<CalendarEntryRow, "id" | "note" | "created_at" | "updated_at">
      >;
      favorites: TableDef<FavoriteRow, Insertable<FavoriteRow, "created_at">,
        [
          { foreignKeyName: "favorites_exercise_id_fkey", columns: ["exercise_id"], isOneToOne: false, referencedRelation: "exercises", referencedColumns: ["id"] }
        ]
      >;
      quotes: TableDef<QuoteRow, Insertable<QuoteRow, "id" | "author" | "active" | "created_at">>;
      body_weight_entries: TableDef<BodyWeightEntryRow, Insertable<BodyWeightEntryRow, "id" | "created_at">>;
    };
    Views: Record<string, never>;
    Functions: {
      is_admin: { Args: Record<string, never>; Returns: boolean };
      is_nickname_available: { Args: { p_nickname: string }; Returns: boolean };
      start_workout_session: { Args: { p_plan_id: string }; Returns: string };
      complete_workout_session: {
        Args: { p_session_id: string; p_notes?: string | null; p_local_date?: string | null };
        Returns: WorkoutSessionRow;
      };
      cancel_workout_session: { Args: { p_session_id: string }; Returns: undefined };
      get_last_exercise_performance: {
        Args: { p_exercise_ids: string[] };
        Returns: LastPerformanceRow[];
      };
      get_user_stats: { Args: Record<string, never>; Returns: UserStatsRow[] };
      get_group_stats: { Args: Record<string, never>; Returns: GroupStatsRow[] };
      get_exercise_records: { Args: { p_exercise_id: string }; Returns: ExerciseRecordsRow[] };
      get_exercise_history: {
        Args: { p_exercise_id: string; p_from?: string | null };
        Returns: ExerciseHistoryRow[];
      };
      get_member_sessions: {
        Args: { p_user_id: string; p_limit?: number };
        Returns: MemberSessionRow[];
      };
      get_member_session_detail: {
        Args: { p_session_id: string };
        Returns: MemberSessionDetail | null;
      };
    };
    Enums: {
      muscle_role: MuscleRole;
      equipment_type: EquipmentType;
      exercise_category: ExerciseCategory;
      session_status: SessionStatus;
      calendar_entry_type: CalendarEntryType;
      weight_unit: WeightUnit;
      theme_preference: ThemePreference;
      user_role: UserRole;
    };
    CompositeTypes: Record<string, never>;
  };
};

export type LastPerformanceRow = {
  exercise_id: string;
  session_id: string;
  started_at: string;
  target_sets: number;
  rep_min: number;
  rep_max: number;
  set_number: number;
  weight: number;
  reps: number;
  rir: number | null;
  is_warmup: boolean;
};

export type UserStatsRow = {
  total_workouts: number;
  total_duration_seconds: number;
  total_volume: number;
  total_sets: number;
  distinct_exercises: number;
  last_workout_at: string | null;
};

export type GroupStatsRow = {
  user_id: string;
  nickname: string;
  total_workouts: number;
  total_duration_seconds: number;
  total_volume: number;
  last_workout_at: string | null;
  member_since: string;
};

export type ExerciseRecordsRow = {
  max_weight: number | null;
  max_weight_reps: number | null;
  max_weight_at: string | null;
  max_reps: number | null;
  max_reps_weight: number | null;
  max_reps_at: string | null;
  best_est_1rm: number | null;
  best_est_1rm_at: string | null;
  max_session_volume: number | null;
  max_session_volume_at: string | null;
  total_sessions: number;
};

export type ExerciseHistoryRow = {
  session_id: string;
  started_at: string;
  max_weight: number;
  max_reps: number;
  top_set_weight: number;
  top_set_reps: number;
  est_1rm: number;
  volume: number;
  sets: number;
};

/** Zeile aus get_member_sessions (Stats: Trainings eines Mitglieds) */
export type MemberSessionRow = {
  session_id: string;
  name: string;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  total_volume: number;
  total_sets: number;
  exercise_names: string[];
};

/** Struktur des jsonb-Ergebnisses von get_member_session_detail */
export type MemberSessionDetailSet = {
  set_number: number;
  weight: number;
  reps: number;
  rir: number | null;
  is_warmup: boolean;
};

export type MemberSessionDetailExercise = {
  id: string;
  sort_order: number;
  target_sets: number;
  rep_min: number;
  rep_max: number;
  exercise: {
    id: string;
    slug: string;
    name: string;
    category: ExerciseCategory;
    equipment: EquipmentType;
  };
  sets: MemberSessionDetailSet[];
};

export type MemberSessionDetail = {
  session: {
    id: string;
    user_id: string;
    nickname: string;
    name: string;
    started_at: string;
    ended_at: string | null;
    duration_seconds: number | null;
    total_volume: number;
    total_sets: number;
    notes: string | null;
  };
  exercises: MemberSessionDetailExercise[];
};

/** Hilfstypen für die App */
export type Tables<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Row"];
export type TablesInsert<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Insert"];
export type TablesUpdate<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Update"];
