module Checks
  module Report
    class Content < ForemanMaintain::Report
      metadata do
        description 'Facts about Katello content'
        confine do
          feature(:katello)
        end
      end

      def run
        # Existing repository counts
        data_field('custom_library_yum_repositories_count') { custom_library_yum_repositories }
        data_field('redhat_library_yum_repositories_count') { redhat_library_yum_repositories }
        data_field('library_debian_repositories_count') { library_repositories('deb') }
        data_field('library_container_repositories_count') { library_repositories('docker') }
        data_field('library_file_repositories_count') { library_repositories('file') }
        data_field('library_python_repositories_count') { library_repositories('python') }
        data_field('library_ansible_collection_repositories_count') do
          library_repositories('ansible_collection')
        end
        data_field('library_ostree_repositories_count') { library_repositories('ostree') }

        # Container content
        data_field('container_manifests_count') { container_manifests_count }
        data_field('container_manifest_lists_count') { container_manifest_lists_count }
        data_field('container_tags_count') { container_tags_count }
        data_field('container_meta_tags_count') { container_meta_tags_count }

        # Aggregate content unit counts
        data_field('rpms_count') { rpms_count }
        data_field('errata_count') { errata_count }
        data_field('module_streams_count') { module_streams_count }
        data_field('file_units_count') { file_units_count }
        data_field('ansible_collections_count') { ansible_collections_count }

        # Rolling content view use and lifecycle environments
        data_field('rolling_content_views_count') { rolling_info[:rolling_content_views_count] }
        data_field('lifecycle_environments_count') { rolling_info[:lifecycle_environments_count] }
        data_field('library_environment_used') { rolling_info[:library_environment_used] }
        data_field('lifecycle_environment_paths_count') { rolling_info[:lifecycle_environment_paths_count] }

        # Flatpak content information
        data_field('flatpak_remotes_count') { flatpak_info[:flatpak_remotes_count] }
        data_field('flatpak_scanned_repositories_count') { flatpak_info[:flatpak_scanned_repositories_count] }
        data_field('flatpak_images_count') { flatpak_info[:flatpak_images_count] }

        # Content export statistics
        data_field('repository_export_histories_count') { export_info[:repository_export_histories_count] }
        data_field('cvv_export_histories_count') { export_info[:cvv_export_histories_count] }
        data_field('library_export_histories_count') { export_info[:library_export_histories_count] }
        data_field('full_export_count') { export_info[:full_export_count] }
        data_field('incremental_export_count') { export_info[:incremental_export_count] }
        data_field('syncable_format_export_count') { export_info[:syncable_format_export_count] }
        data_field('regular_format_export_count') { export_info[:regular_format_export_count] }

        # Red Hat repository information
        data_field('enabled_rh_repos_total_count') { rh_info[:enabled_rh_repos_total_count] }
        data_field('enabled_rh_file_repos_count') { rh_info[:enabled_rh_file_repos_count] }
        merge_data('rh_yum_repo_arch_count') { rh_info[:rh_yum_repo_arch_count] || {} }
        data_field('disabled_rh_repos_destroy_audit_events_count') { rh_info[:disabled_rh_repos_destroy_audit_events_count] }
        data_field('disabled_rh_repos_count') { rh_info[:disabled_rh_repos_count] }

        # Sync plans usage
        data_field('sync_plans_used') { sync_plans_used }
        data_field('sync_plans_count') { sync_plans_count }

        # Registry naming patterns usage
        data_field('registry_naming_patterns_count') { registry_naming_patterns_count }
      end

      def rolling_info
        @rolling_info ||= rolling_content_view_usage
      end

      def flatpak_info
        @flatpak_info ||= flatpak_content_info
      end

      def export_info
        @export_info ||= content_export_stats
      end

      def rh_info
        @rh_info ||= redhat_repository_info
      end

      def custom_library_yum_repositories
        query_snippet =
          <<-SQL
            "katello_root_repositories"
              WHERE "katello_root_repositories"."id" NOT IN
              (SELECT "katello_root_repositories"."id" FROM "katello_root_repositories" INNER JOIN "katello_products"
                ON "katello_products"."id" = "katello_root_repositories"."product_id" INNER JOIN "katello_providers"
                ON "katello_providers"."id" = "katello_products"."provider_id" WHERE "katello_providers"."provider_type" = 'Red Hat')
              AND "katello_root_repositories"."content_type" = 'yum'
          SQL
        sql_count(query_snippet)
      end

      def redhat_library_yum_repositories
        query_snippet =
          <<-SQL
            "katello_root_repositories"
              INNER JOIN "katello_products" ON "katello_products"."id" = "katello_root_repositories"."product_id"
              INNER JOIN "katello_providers" ON "katello_providers"."id" = "katello_products"."provider_id"
                WHERE "katello_providers"."provider_type" = 'Red Hat'
              AND "katello_root_repositories"."content_type" = 'yum'
          SQL
        sql_count(query_snippet)
      end

      def library_repositories(content_type)
        sql_count("katello_root_repositories WHERE content_type = '#{content_type}'")
      end

      def container_manifests_count
        # Count distinct container manifests present in container repositories.
        # Exclude flatpaks which also use the manifest tables.
        sql = <<-SQL
          katello_repository_docker_manifests rdm
          INNER JOIN katello_docker_manifests dm ON rdm.docker_manifest_id = dm.id
          INNER JOIN katello_repositories r ON rdm.repository_id = r.id
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          WHERE rr.content_type = 'docker'
            AND COALESCE(dm.is_flatpak, false) = false
        SQL
        sql_count(sql, column: 'DISTINCT dm.id') || 0
      end

      def container_manifest_lists_count
        sql = <<-SQL
          katello_repository_docker_manifest_lists rdml
          INNER JOIN katello_repositories r ON rdml.repository_id = r.id
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          WHERE rr.content_type = 'docker'
        SQL
        sql_count(sql, column: 'DISTINCT rdml.docker_manifest_list_id') || 0
      end

      def container_tags_count
        sql = <<-SQL
          katello_repository_docker_tags rdt
          INNER JOIN katello_repositories r ON rdt.repository_id = r.id
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          WHERE rr.content_type = 'docker'
        SQL
        sql_count(sql) || 0
      end

      def container_meta_tags_count
        sql = <<-SQL
          katello_repository_docker_meta_tags rdmt
          INNER JOIN katello_repositories r ON rdmt.repository_id = r.id
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          WHERE rr.content_type = 'docker'
        SQL
        sql_count(sql) || 0
      end

      def rpms_count
        sql_count('katello_rpms') || 0
      end

      def errata_count
        sql_count('katello_errata') || 0
      end

      def module_streams_count
        sql_count('katello_module_streams') || 0
      end

      def file_units_count
        sql_count('katello_files') || 0
      end

      def ansible_collections_count
        sql_count('katello_ansible_collections') || 0
      end

      # Rolling content view usage information
      def rolling_content_view_usage
        result = {}

        # Count of rolling content views
        result[:rolling_content_views_count] = sql_count("katello_content_views WHERE rolling = true") || 0

        # Count of lifecycle environments
        result[:lifecycle_environments_count] = sql_count("katello_environments") || 0

        # Check if Library environment is used
        library_env_count = sql_count("katello_environments WHERE library = true") || 0
        result[:library_environment_used] = library_env_count.positive?

        # Lifecycle environment paths: environments are chained via katello_environment_priors.
        # A "path" is defined as a complete chain from the Library environment to a leaf
        # environment (per organization). We count distinct leaf environments reachable from
        # each org's Library.
        env_paths_cte = <<~SQL
          WITH RECURSIVE env_tree AS (
            SELECT e.id, e.organization_id
            FROM katello_environments e
            WHERE e.library = true

            UNION ALL

            SELECT child.id, child.organization_id
            FROM env_tree parent
            INNER JOIN katello_environment_priors p ON p.prior_id = parent.id
            INNER JOIN katello_environments child ON child.id = p.environment_id
          ), leaf_envs AS (
            SELECT t.id, t.organization_id
            FROM env_tree t
            LEFT JOIN katello_environment_priors p ON p.prior_id = t.id
            WHERE p.prior_id IS NULL
          ), distinct_leaf_envs AS (
            SELECT DISTINCT organization_id, id FROM leaf_envs
          )
        SQL
        result[:lifecycle_environment_paths_count] = sql_count('distinct_leaf_envs', cte: env_paths_cte) || 0

        result
      end

      # Flatpak content information
      def flatpak_content_info
        result = {}

        if table_exists('katello_flatpak_remotes')
          result[:flatpak_remotes_count] = sql_count('katello_flatpak_remotes')
        end

        if table_exists('katello_flatpak_remote_repositories')
          result[:flatpak_scanned_repositories_count] = sql_count('katello_flatpak_remote_repositories')
        end

        if table_exists('katello_flatpak_remote_repository_manifests')
          result[:flatpak_images_count] = sql_count('katello_flatpak_remote_repository_manifests')
        end

        result
      end

      # Content export statistics
      def content_export_stats
        result = {}

        return result unless table_exists('katello_content_view_version_export_histories')

        result[:repository_export_histories_count] = 0
        result[:cvv_export_histories_count] = sql_count('katello_content_view_version_export_histories') || 0
        result[:library_export_histories_count] = 0
        result[:full_export_count] = (sql_count("katello_content_view_version_export_histories WHERE export_type = 'complete'") || 0)
        result[:incremental_export_count] = (sql_count("katello_content_view_version_export_histories WHERE export_type = 'incremental'") || 0)
        result[:syncable_format_export_count] = 0
        result[:regular_format_export_count] = 0

        # If we can join back to content views, split export histories by export type.
        if table_exists('katello_content_view_versions') && table_exists('katello_content_views')
          base_join = <<-SQL
            katello_content_view_version_export_histories h
            INNER JOIN katello_content_view_versions cvv ON h.content_view_version_id = cvv.id
            INNER JOIN katello_content_views cv ON cvv.content_view_id = cv.id
          SQL

          if table_exists('katello_content_views') &&
             sql_count("information_schema.columns WHERE table_name = 'katello_content_views' AND column_name = 'generated_for'").to_i > 0
            result[:library_export_histories_count] =
              (sql_count("#{base_join} WHERE cv.generated_for IN ('library_export', 'library_export_syncable')") || 0)
            result[:repository_export_histories_count] =
              (sql_count("#{base_join} WHERE cv.generated_for IN ('repository_export', 'repository_export_syncable')") || 0)
          end
        end

        # Export format is stored inside serialized metadata (text). We infer counts via pattern matching.
        if sql_count("information_schema.columns WHERE table_name = 'katello_content_view_version_export_histories' AND column_name = 'metadata'").to_i > 0
          # Rails serialize(:metadata, Hash) typically stores YAML with symbol keys (e.g. "\n:format: syncable\n")
          result[:syncable_format_export_count] = (
            sql_count("katello_content_view_version_export_histories WHERE metadata LIKE '%:format: syncable%' OR metadata LIKE '%format: syncable%'") || 0
          )
          result[:regular_format_export_count] = (
            sql_count("katello_content_view_version_export_histories WHERE metadata LIKE '%:format: importable%' OR metadata LIKE '%format: importable%'") || 0
          )
        end

        result
      end

      # Red Hat repository information
      def redhat_repository_info
        result = {}

        # For this report, "enabled/disabled" for Red Hat repositories matches the Red Hat Repositories page:
        # a repository is enabled if the corresponding Katello::Repository exists; disabling destroys it.
        enabled_repos_sql = <<-SQL
          katello_repositories r
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          INNER JOIN katello_products p ON rr.product_id = p.id
          INNER JOIN katello_providers prov ON p.provider_id = prov.id
          INNER JOIN katello_content_view_versions cvv ON r.content_view_version_id = cvv.id
          INNER JOIN katello_content_views cv ON cvv.content_view_id = cv.id
          INNER JOIN katello_environments e ON r.environment_id = e.id
          WHERE prov.provider_type = 'Red Hat'
            AND cv.default = true
            AND e.library = true
            AND r.library_instance_id IS NULL
        SQL

        # Total enabled RH repos count (current state)
        result[:enabled_rh_repos_total_count] = sql_count(enabled_repos_sql) || 0

        # Number of enabled Red Hat file repos (current state)
        result[:enabled_rh_file_repos_count] = sql_count("#{enabled_repos_sql} AND rr.content_type = 'file'") || 0

        # Architecture counts for enabled RH yum repos (current state)
        sql = <<-SQL
          SELECT rr.arch, COUNT(*) AS repo_count
          FROM katello_repositories r
          INNER JOIN katello_root_repositories rr ON r.root_id = rr.id
          INNER JOIN katello_products p ON rr.product_id = p.id
          INNER JOIN katello_providers prov ON p.provider_id = prov.id
          INNER JOIN katello_content_view_versions cvv ON r.content_view_version_id = cvv.id
          INNER JOIN katello_content_views cv ON cvv.content_view_id = cv.id
          INNER JOIN katello_environments e ON r.environment_id = e.id
          WHERE prov.provider_type = 'Red Hat'
            AND cv.default = true
            AND e.library = true
            AND r.library_instance_id IS NULL
            AND rr.content_type = 'yum'
            AND rr.arch IS NOT NULL
          GROUP BY rr.arch
          ORDER BY rr.arch
        SQL
        result[:rh_yum_repo_arch_count] = query(sql).to_h do |row|
          [row['arch'], row['repo_count'].to_i]
        end

        # Disabled RH repos: repositories that were destroyed (disable button or manual destroy).
        # We infer this from repository destroy audits for Red Hat library-instance repos in the default CV.
        destroyed_repo_audits_sql = <<-SQL
          (
            SELECT
              id,
              created_at,
              substring(audited_changes from 'root_id: ([0-9]+)')::int AS root_id,
              substring(audited_changes from 'environment_id: ([0-9]+)')::int AS environment_id,
              substring(audited_changes from 'content_view_version_id: ([0-9]+)')::int AS content_view_version_id,
              substring(audited_changes from 'relative_path: (.*)') AS relative_path
            FROM audits
            WHERE auditable_type = 'Katello::Repository'
              AND action = 'destroy'
              AND audited_changes LIKE '%root_id:%'
          ) a
          INNER JOIN katello_root_repositories rr ON rr.id = a.root_id
          INNER JOIN katello_products p ON rr.product_id = p.id
          INNER JOIN katello_providers prov ON p.provider_id = prov.id
          INNER JOIN katello_environments e ON e.id = a.environment_id
          INNER JOIN katello_content_view_versions cvv ON cvv.id = a.content_view_version_id
          INNER JOIN katello_content_views cv ON cv.id = cvv.content_view_id
          WHERE prov.provider_type = 'Red Hat'
            AND e.library = true
            AND cv.default = true
        SQL

        # Count of destroy events (can include repeated disable/enable cycles)
        result[:disabled_rh_repos_destroy_audit_events_count] = sql_count(destroyed_repo_audits_sql) || 0
        # Count of distinct repos destroyed, identified by relative_path
        result[:disabled_rh_repos_count] = sql_count(destroyed_repo_audits_sql, column: 'DISTINCT a.relative_path') || 0

        result
      end

      # Sync plans usage
      def sync_plans_used
        if table_exists('katello_sync_plans')
          sql_count('katello_sync_plans') > 0
        else
          false
        end
      end

      def sync_plans_count
        if table_exists('katello_sync_plans')
          sql_count('katello_sync_plans')
        else
          0
        end
      end

      # Registry naming patterns usage
      def registry_naming_patterns_count
        sql_count("katello_environments WHERE registry_name_pattern IS NOT NULL AND registry_name_pattern != ''") || 0
      end

    end
  end
end
