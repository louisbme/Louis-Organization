-- ============================================================
-- 0008_member_sessions.sql
-- Mitglieder-Detailansicht in den Stats: abgeschlossene Trainings
-- eines Mitglieds samt Übungen und Sätzen (nur lesend, nur für
-- angemeldete Benutzer).
-- ============================================================

-- ------------------------------------------------------------
-- Trainingsliste eines Mitglieds
-- ------------------------------------------------------------
create or replace function public.get_member_sessions(p_user_id uuid, p_limit integer default 100)
returns table (
  session_id uuid,
  name text,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer,
  total_volume numeric,
  total_sets integer,
  exercise_names text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  return query
  select
    s.id as session_id,
    s.name,
    s.started_at,
    s.ended_at,
    s.duration_seconds,
    s.total_volume,
    s.total_sets,
    coalesce(
      (select array_agg(e.name order by se.sort_order)
         from public.workout_session_exercises se
         join public.exercises e on e.id = se.exercise_id
        where se.session_id = s.id),
      '{}'::text[]
    ) as exercise_names
  from public.workout_sessions s
  where s.user_id = p_user_id
    and s.status = 'completed'
  order by s.started_at desc
  limit coalesce(p_limit, 100);
end;
$$;
revoke all on function public.get_member_sessions(uuid, integer) from public;
grant execute on function public.get_member_sessions(uuid, integer) to authenticated;

-- ------------------------------------------------------------
-- Detail eines abgeschlossenen Trainings (Übungen + Sätze) als JSON
-- Gibt null zurück, wenn die Session nicht existiert oder nicht abgeschlossen ist.
-- ------------------------------------------------------------
create or replace function public.get_member_session_detail(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id,
      'user_id', s.user_id,
      'nickname', coalesce(p.nickname, 'Benutzer'),
      'name', s.name,
      'started_at', s.started_at,
      'ended_at', s.ended_at,
      'duration_seconds', s.duration_seconds,
      'total_volume', s.total_volume,
      'total_sets', s.total_sets,
      'notes', s.notes
    ),
    'exercises', coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id', se.id,
           'sort_order', se.sort_order,
           'target_sets', se.target_sets,
           'rep_min', se.rep_min,
           'rep_max', se.rep_max,
           'exercise', jsonb_build_object(
             'id', e.id,
             'slug', e.slug,
             'name', e.name,
             'category', e.category,
             'equipment', e.equipment
           ),
           'sets', coalesce(
             (select jsonb_agg(
                jsonb_build_object(
                  'set_number', ws.set_number,
                  'weight', ws.weight,
                  'reps', ws.reps,
                  'rir', ws.rir,
                  'is_warmup', ws.is_warmup
                ) order by ws.set_number)
                from public.workout_sets ws
               where ws.session_exercise_id = se.id
                 and ws.completed),
             '[]'::jsonb
           )
         ) order by se.sort_order)
         from public.workout_session_exercises se
         join public.exercises e on e.id = se.exercise_id
        where se.session_id = s.id),
      '[]'::jsonb
    )
  )
  into v_result
  from public.workout_sessions s
  left join public.profiles p on p.id = s.user_id
  where s.id = p_session_id
    and s.status = 'completed';

  return v_result;
end;
$$;
revoke all on function public.get_member_session_detail(uuid) from public;
grant execute on function public.get_member_session_detail(uuid) to authenticated;
