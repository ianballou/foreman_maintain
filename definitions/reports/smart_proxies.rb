module Checks
  module Report
    class SmartProxies < ForemanMaintain::Report
      metadata do
        description 'Facts about Smart Proxies related to Katello content'
        confine do
          feature(:katello)
        end
      end

      def run
        # Content source / external Smart Proxies
        data_field('smart_proxies_with_assigned_hosts_count') { smart_proxies_info[:smart_proxies_with_assigned_hosts_count] }
        data_field('hosts_with_assigned_smart_proxy_count') { smart_proxies_info[:hosts_with_assigned_smart_proxy_count] }
        data_field('hosts_per_smart_proxy_min') { smart_proxies_info[:hosts_per_smart_proxy_min] }
        data_field('hosts_per_smart_proxy_median') { smart_proxies_info[:hosts_per_smart_proxy_median] }
        data_field('hosts_per_smart_proxy_avg') { smart_proxies_info[:hosts_per_smart_proxy_avg] }
        data_field('hosts_per_smart_proxy_max') { smart_proxies_info[:hosts_per_smart_proxy_max] }
        data_field('smart_proxies_syncing_library') { smart_proxies_info[:smart_proxies_syncing_library] }
        data_field('smart_proxies_syncing_multiple_lifecycle_environments') do
          smart_proxies_info[:smart_proxies_syncing_multiple_lifecycle_environments]
        end
      end

      private

      def smart_proxies_info
        @smart_proxies_info ||= content_sources_smart_proxies_info
      end

      # Content source / external Smart Proxies information
      def content_sources_smart_proxies_info
        result = {}

        # NOTE: Smart Proxy names/identities are considered private data.
        # We therefore avoid reporting per-smart-proxy breakdowns keyed by proxy name.
        #
        # Count of hosts assigned per Smart Proxy (aggregated)
        sql = <<-SQL
          SELECT sp.id as smart_proxy_id, COUNT(cf.id) as host_count
          FROM smart_proxies sp
          LEFT JOIN katello_content_facets cf ON sp.id = cf.content_source_id
          WHERE sp.id IN (SELECT DISTINCT content_source_id FROM katello_content_facets WHERE content_source_id IS NOT NULL)
          GROUP BY sp.id
        SQL
        counts = query(sql).map { |row| row['host_count'].to_i }
        result.merge!(hosts_per_smart_proxy_aggregates(counts))

        # Smart Proxies that sync library
        sql = <<-SQL
          smart_proxies sp
          INNER JOIN katello_capsule_lifecycle_environments kcle ON sp.id = kcle.capsule_id
          INNER JOIN katello_environments ke ON kcle.lifecycle_environment_id = ke.id
          WHERE ke.library = true
        SQL
        result[:smart_proxies_syncing_library] = (sql_count(sql, column: 'DISTINCT sp.id') || 0)

        # Smart Proxies that sync more than one lifecycle environment
        sql = <<-SQL
          (SELECT capsule_id, COUNT(DISTINCT lifecycle_environment_id) as env_count
           FROM katello_capsule_lifecycle_environments
           GROUP BY capsule_id
           HAVING COUNT(DISTINCT lifecycle_environment_id) > 1) multi_env_capsules
        SQL
        result[:smart_proxies_syncing_multiple_lifecycle_environments] = (sql_count(sql) || 0)

        result
      end

      def hosts_per_smart_proxy_aggregates(counts)
        counts = Array(counts).compact.map(&:to_i).sort
        smart_proxies_with_assigned_hosts_count = counts.size
        hosts_with_assigned_smart_proxy_count = counts.sum

        min = counts.first || 0
        max = counts.last || 0
        avg = smart_proxies_with_assigned_hosts_count.positive? ? (hosts_with_assigned_smart_proxy_count.to_f / smart_proxies_with_assigned_hosts_count) : 0.0
        median = if smart_proxies_with_assigned_hosts_count.zero?
                   0
                 else
                   mid = smart_proxies_with_assigned_hosts_count / 2
                   if smart_proxies_with_assigned_hosts_count.odd?
                     counts[mid]
                   else
                     ((counts[mid - 1] + counts[mid]) / 2.0)
                   end
                 end

        {
          smart_proxies_with_assigned_hosts_count: smart_proxies_with_assigned_hosts_count,
          hosts_with_assigned_smart_proxy_count: hosts_with_assigned_smart_proxy_count,
          hosts_per_smart_proxy_min: min,
          hosts_per_smart_proxy_median: median,
          hosts_per_smart_proxy_avg: avg,
          hosts_per_smart_proxy_max: max,
        }
      end
    end
  end
end

