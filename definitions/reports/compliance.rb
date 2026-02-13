module Reports
  class Compliance < ForemanMaintain::Report
    metadata do
      description 'Check if OpenSCAP is used'
    end

    def run
      self.data = {}
      mapping = {
        'policy':
          'foreman_openscap_policies',
        'policy_with_tailoring_file':
          'foreman_openscap_policies WHERE tailoring_file_id IS NOT NULL',
        'scap_contents':
          "foreman_openscap_scap_contents",
        'non_default_scap_contents':
          "foreman_openscap_scap_contents WHERE NOT original_filename LIKE 'ssg-rhel%-ds.xml'",
        'arf_report_last_year':
          "reports WHERE type = 'ForemanOpenscap::ArfReport'
                      AND reported_at < NOW() - INTERVAL '1 year'",
      }

      mapping.each do |k, query|
        data["compliance_#{k}_count"] = sql_count(query)
      end

      # SAT-41501 / reporting: SCAP tailoring usage summary
      policies_total = table_exists('foreman_openscap_policies') ? (sql_count('foreman_openscap_policies') || 0) : 0
      policies_with_tailoring = if table_exists('foreman_openscap_policies')
                                  (sql_count("foreman_openscap_policies WHERE tailoring_file_id IS NOT NULL") || 0)
                                else
                                  0
                                end
      data['scap_tailoring_used'] = policies_with_tailoring.positive?
      data['scap_policies_with_tailoring'] = policies_with_tailoring
      data['scap_policies_without_tailoring'] = [policies_total - policies_with_tailoring, 0].max
    end
  end
end
