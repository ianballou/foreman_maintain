module Reports
  class Dashboard < ForemanMaintain::Report
    metadata do
      description 'Facts about the Foreman dashboard'
    end

    def run
      data_field('dashboard_widgets_count') { dashboard_widgets_count }
    end

    private

    def dashboard_widgets_count
      return 0 unless table_exists('widgets')
      sql_count('widgets') || 0
    end
  end
end

