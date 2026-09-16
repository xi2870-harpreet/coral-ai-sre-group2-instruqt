resource "lab" "main" {
  title       = "AI SRE: Root-Cause an Incident with One SQL Query (Group 2)"
  description = <<-EOF
  This is the Skeleton Lab.
  You can use this as a minimal starting point for developing labs.
  EOF

  # timelimit and idle are both required on every lab.
  settings {
    timelimit {
      duration = "1h"
    }

    idle {
      enabled = true
      timeout = "15m"
    }
  }

  layout = resource.layout.single_panel
}
