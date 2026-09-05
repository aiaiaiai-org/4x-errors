# frozen_string_literal: true

# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

require 'sequel'

module Aiaiaiai
  module Errors
    module Collector
      # Persistence for the whole domain.
      #
      # Raw occurrences are appended and never rewritten. The registry and the
      # family mapping are maintained alongside them as a revisable
      # interpretation of what those occurrences mean.
      class Store
        # Following a relation from cause to effect, and back.
        FORWARD = %w[root_cause_of contributes_to].freeze
        BACKWARD = %w[derivative_of triggered_by].freeze

        # Serialises writes to the causal graph so that two concurrent
        # transactions cannot each observe an acyclic graph and jointly create
        # a cycle.
        CAUSAL_GRAPH_LOCK = 0x4e5252

        class CycleRejected < StandardError
        end

        def initialize(db)
          @db = db
        end

        attr_reader :db

        # Records one request atomically: either every occurrence and every
        # relation in it is stored, or none is.
        def record(events:, relations:, received_at:)
          db.transaction do
            stored = events.map { |event| record_event(event, received_at) }
            ids_by_local_ref = events.each_with_index.to_h do |event, index|
              [event[:local_ref], stored[index][:event_id]]
            end
            ids_by_local_ref.delete(nil)

            relation_results = relations.map do |relation|
              record_relation(relation, ids_by_local_ref)
            end
            { events: stored, relations: relation_results }
          end
        end

        # Appends one occurrence. A repeated occurrence_key resolves to the
        # occurrence already stored, so a retrying reporter never duplicates.
        def record_event(event, received_at)
          row = event.except(:local_ref).merge(received_at: received_at)

          register_error(row[:error_id], received_at)
          resolve_reported_family(row, received_at)

          inserted = db[:error_events]
                     .insert_conflict(target: %i[project occurrence_key],
                                      conflict_where: Sequel.~(occurrence_key: nil))
                     .returning(:id)
                     .insert(row)
          return { event_id: inserted.first[:id], duplicate: false } unless inserted.empty?

          existing = db[:error_events]
                     .where(project: row[:project], occurrence_key: row[:occurrence_key])
                     .get(:id)
          { event_id: existing, duplicate: true }
        end

        def resolve_reported_family(row, received_at)
          return if row[:reported_family_id].nil?

          register_family(row[:reported_family_id], received_at)
          record_reported_membership(row[:error_id], row[:reported_family_id], received_at)
        end

        def register_error(error_id, seen_at)
          db[:error_definitions]
            .insert_conflict(target: :error_id, update: { last_seen_at: seen_at,
                                                          updated_at: seen_at })
            .insert(error_id: error_id, auto_registered: true,
                    first_seen_at: seen_at, last_seen_at: seen_at,
                    created_at: seen_at, updated_at: seen_at)
        end

        def register_family(family_id, seen_at)
          db[:error_families]
            .insert_conflict(target: :family_id)
            .insert(family_id: family_id, title: family_id,
                    created_at: seen_at, updated_at: seen_at)
        end

        # A family reported by an SDK is recorded once. If curation later
        # supersedes that membership, reports do not resurrect it: the
        # superseded row stays and no new one is created.
        def record_reported_membership(error_id, family_id, seen_at)
          existing = db[:error_family_memberships].where(error_id: error_id, family_id: family_id)
          return unless existing.empty?

          db[:error_family_memberships].insert(
            error_id: error_id, family_id: family_id,
            confidence: 1.0, evidence: Sequel.pg_array(%w[explicit_reporter_relation], :text),
            source: 'reported', created_at: seen_at
          )
        rescue Sequel::UniqueConstraintViolation
          # Another transaction recorded the same membership first.
          nil
        end

        # Supersedes an active membership and, optionally, states the family
        # the error belongs to instead. Raw occurrences are untouched: they
        # keep the family their reporter claimed at the time.
        def reclassify(error_id:, from_family_id:, to_family_id: nil, evidence: %w[human_review],
                       confidence: 1.0, source: 'curated', reason: nil, at: Time.now.utc)
          db.transaction do
            db[:error_family_memberships]
              .where(error_id: error_id, family_id: from_family_id, superseded_at: nil)
              .update(superseded_at: at, superseded_reason: reason)

            next nil if to_family_id.nil?

            register_family(to_family_id, at)
            db[:error_family_memberships].insert_conflict.insert(
              error_id: error_id, family_id: to_family_id,
              confidence: confidence, evidence: Sequel.pg_array(Array(evidence), :text),
              source: source, note: reason, created_at: at
            )
          end
        end

        def active_families(error_id)
          db[:error_family_memberships]
            .where(error_id: error_id, superseded_at: nil)
            .select_order_map(:family_id)
        end

        def family_members(family_id)
          db[:error_family_memberships]
            .where(family_id: family_id, superseded_at: nil)
            .select_order_map(:error_id)
        end

        # Error ids this error is known to cause, directly.
        def effects_of(error_id)
          directed_neighbours(error_id, :effects)
        end

        # Error ids known to cause this error, directly.
        def causes_of(error_id)
          directed_neighbours(error_id, :causes)
        end

        private

        # Causal neighbours in one direction. Both spellings of a causal
        # edge are followed, so "root_cause_of" and "derivative_of" answer the
        # same question from opposite sides.
        def directed_neighbours(error_id, direction)
          forward_match, forward_read, backward_match, backward_read =
            if direction == :effects
              %i[source_error_id target_error_id target_error_id source_error_id]
            else
              %i[target_error_id source_error_id source_error_id target_error_id]
            end

          forward = neighbours(FORWARD, forward_match, error_id, forward_read)
          backward = neighbours(BACKWARD, backward_match, error_id, backward_read)
          (forward + backward).uniq.sort
        end

        def neighbours(types, match_column, error_id, read_column)
          db[:error_relations]
            .where(:relation_type => types, match_column => error_id)
            .select_map(read_column)
        end

        def record_relation(relation, ids_by_local_ref)
          source = resolve_endpoint(relation[:source], ids_by_local_ref)
          target = resolve_endpoint(relation[:target], ids_by_local_ref)
          error_level = relation[:source].key?(:error_id)

          if error_level
            insert_error_relation(relation, source,
                                  target)
          else
            insert_event_relation(relation, source,
                                  target)
          end
        end

        def resolve_endpoint(endpoint, ids_by_local_ref)
          endpoint[:error_id] || endpoint[:event_id] || ids_by_local_ref.fetch(endpoint[:local_ref])
        end

        def insert_error_relation(relation, source, target)
          guard_against_cycle(:error, relation[:type], source, target)
          register_error(source, relation[:created_at])
          register_error(target, relation[:created_at])
          insert_relation(:error_relations, relation,
                          columns: %i[source_error_id target_error_id], endpoints: [source, target])
        end

        def insert_event_relation(relation, source, target)
          guard_against_cycle(:event, relation[:type], source, target)
          insert_relation(:event_relations, relation,
                          columns: %i[source_event_id target_event_id], endpoints: [source, target])
        end

        def insert_relation(table, relation, columns:, endpoints:)
          source_column, target_column = columns
          row = columns.zip(endpoints).to_h.merge(
            relation_type: relation[:type],
            confidence: relation[:confidence],
            evidence: Sequel.pg_array(Array(relation[:evidence]), :text),
            note: relation[:note],
            created_by: relation[:created_by] || 'reporter',
            created_at: relation[:created_at]
          )
          inserted = db[table]
                     .insert_conflict(target: [source_column, :relation_type, target_column])
                     .returning(:id)
                     .insert(row)

          { type: relation[:type], stored: !inserted.empty? }
        end

        # An effect may never be, transitively, its own cause.
        def guard_against_cycle(level, relation_type, source, target)
          edge = Protocol::Vocabulary.causal_edge(relation_type, source, target)
          return if edge.nil?

          db.get(Sequel.function(:pg_advisory_xact_lock, CAUSAL_GRAPH_LOCK))
          cause, effect = edge
          return unless reachable?(level, from: effect, to: cause)

          raise CycleRejected, "#{source} #{relation_type} #{target} closes a causal cycle"
        end

        def reachable?(level, from:, to:)
          table, source_column, target_column, cast =
            if level == :error
              %w[error_relations source_error_id target_error_id text]
            else
              %w[event_relations source_event_id target_event_id uuid]
            end

          sql = <<~SQL
            WITH RECURSIVE reachable(node) AS (
              SELECT CAST(? AS #{cast})
              UNION
              SELECT CASE WHEN r.relation_type IN ('root_cause_of', 'contributes_to')
                          THEN r.#{target_column} ELSE r.#{source_column} END
              FROM #{table} r, reachable
              WHERE (r.relation_type IN ('root_cause_of', 'contributes_to') AND r.#{source_column} = reachable.node)
                 OR (r.relation_type IN ('derivative_of', 'triggered_by') AND r.#{target_column} = reachable.node)
            )
            SELECT 1 AS found FROM reachable WHERE node = CAST(? AS #{cast}) LIMIT 1
          SQL

          !db.fetch(sql, from, to).first.nil?
        end
      end
    end
  end
end
