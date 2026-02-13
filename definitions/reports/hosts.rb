module Checks
  module Report
    class Hosts < ForemanMaintain::Report
      metadata do
        description 'Facts about hosts related to Katello content'
        confine do
          feature(:katello)
        end
      end

      def run
        # MultiCV (Multiple Content View) information
        data_field('hosts_with_multiple_cv_environments') { multicv_info[:hosts_with_multiple_cv_environments] }
        data_field('activation_keys_with_multiple_cv_environments') { multicv_info[:activation_keys_with_multiple_cv_environments] }
        data_field('hosts_with_multiple_cv_environments_including_rolling') do
          multicv_info[:hosts_with_multiple_cv_environments_including_rolling]
        end
      end

      private

      def multicv_info
        @multicv_info ||= multi_cv_info
      end

      # MultiCV (Multiple Content View) information
      def multi_cv_info
        result = {}

        if table_exists('katello_content_view_environment_content_facets')
          # Hosts assigned to multiple content view environments
          sql = <<-SQL
            (SELECT content_facet_id, COUNT(DISTINCT content_view_environment_id) as cv_env_count
             FROM katello_content_view_environment_content_facets
             GROUP BY content_facet_id
             HAVING COUNT(DISTINCT content_view_environment_id) > 1) multi_cv_hosts
          SQL
          result[:hosts_with_multiple_cv_environments] = sql_count(sql)
        end

        if table_exists('katello_content_view_environment_activation_keys')
          # Activation keys assigned to multiple content view environments
          sql = <<-SQL
            (SELECT activation_key_id, COUNT(DISTINCT content_view_environment_id) as cv_env_count
             FROM katello_content_view_environment_activation_keys
             GROUP BY activation_key_id
             HAVING COUNT(DISTINCT content_view_environment_id) > 1) multi_cv_keys
          SQL
          result[:activation_keys_with_multiple_cv_environments] = sql_count(sql)
        end

        # Hosts with multiple CV environments that include rolling content views
        if table_exists('katello_content_view_environment_content_facets') &&
           table_exists('katello_content_view_environments') &&
           table_exists('katello_content_views')
          sql = <<-SQL
            (SELECT DISTINCT cve_cf.content_facet_id
             FROM katello_content_view_environment_content_facets cve_cf
             INNER JOIN katello_content_view_environments cve ON cve_cf.content_view_environment_id = cve.id
             INNER JOIN katello_content_views cv ON cve.content_view_id = cv.id
             WHERE cv.rolling = true
             AND cve_cf.content_facet_id IN (
               SELECT content_facet_id
               FROM katello_content_view_environment_content_facets
               GROUP BY content_facet_id
               HAVING COUNT(DISTINCT content_view_environment_id) > 1
             )) rolling_multi_cv_hosts
          SQL
          result[:hosts_with_multiple_cv_environments_including_rolling] = sql_count(sql)
        end

        result
      end
    end
  end
end

