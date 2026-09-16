resource "lab" "main" {
  title       = "AI SRE: Root-Cause an Incident with One SQL Query"
  description = "Coral is the data engine for enterprise AI - one SQL connection that lets agents query APIs, databases, and files as if they were a single dataset.\n\nIn this hands-on lab you step into the on-call seat. A three-service shop runs in Kubernetes with Prometheus watching it, logs streaming to disk, and a support-ticket export sitting in a Parquet file. When a bad deploy takes payments down, you will root-cause it the Coral way: one SQL JOIN across alerts, pod state, and error logs - first by hand, then hands-free through Claude Code over MCP.\n\nYou will finish by proving the governance story: Coral is read-only by design, and extending the catalog to your own API takes fifteen lines of YAML."

  settings {
    timelimit {
      duration = "1h"
    }

    idle {
      enabled = true
      timeout = "10m"
    }
  }

  layout = resource.layout.main

  content {
    chapter "investigation" {
      title = "AI SRE Investigation"

      page "meet_the_stack" {
        reference = resource.page.meet_the_stack
      }

      page "one_sql_connection" {
        reference = resource.page.one_sql_connection
      }

      page "agent_online" {
        reference = resource.page.agent_online
      }

      page "the_incident" {
        reference = resource.page.the_incident
      }

      page "read_only_by_design" {
        reference = resource.page.read_only_by_design
      }
    }
  }
}
