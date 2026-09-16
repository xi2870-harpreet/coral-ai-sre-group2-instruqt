# Challenge 1: Meet the Stack You're On Call For
resource "task" "meet_the_stack" {
  description = "Tour the shop, kubectl, Prometheus, and the raw data files."

  config {
    target = resource.vm.k8s
  }

  condition "environment_toured" {
    description = "Confirm the environment is healthy and the data plane is seeded"

    check {
      script          = "scripts/task/meet_the_stack/check.sh"
      failure_message = "The environment isn't fully up yet, or hasn't been toured. Give it a few seconds and try again."
    }
  }
}

# Challenge 2: One SQL Connection
resource "task" "one_sql_connection" {
  description = "Discover the Coral catalog and run a cross-source JOIN."

  config {
    target = resource.vm.k8s
  }

  condition "first_join_saved" {
    description = "Run the Step 4 cross-source JOIN and save the evidence"

    check {
      script          = "scripts/task/one_sql_connection/check.sh"
      failure_message = "Run the Step 4 cross-source JOIN in the Terminal - it saves its output to /root/answers/first-join.txt."
    }
  }
}

# Challenge 3: Agent Online
resource "task" "agent_online" {
  description = "Register Coral with Claude Code over MCP and run an agent query."

  config {
    target = resource.vm.k8s
  }

  condition "agent_wired" {
    description = "Register Coral's MCP server with Claude Code and leave a marker"

    check {
      script          = "scripts/task/agent_online/check.sh"
      failure_message = "Claude Code doesn't know about Coral yet, or the Step 3 marker hasn't been recorded."
    }
  }
}

# Challenge 4: Incident - Checkout Is Down
resource "task" "the_incident" {
  description = "Root-cause the bad deploy with one cross-source JOIN and submit the answer."

  config {
    target = resource.vm.k8s
  }

  condition "root_cause_submitted" {
    description = "Investigate the incident and submit the root-cause service"

    setup {
      script = "scripts/task/the_incident/setup.sh"
    }

    check {
      script          = "scripts/task/the_incident/check.sh"
      failure_message = "No correct answer recorded yet. Investigate with Coral, then run: submit \"<root-cause-service>\""
    }
  }
}

# Challenge 5: Read-Only by Design
resource "task" "read_only_by_design" {
  description = "Prove Coral has no write path, then extend the catalog with a custom spec."

  config {
    target = resource.vm.k8s
  }

  condition "governance_and_extension_proven" {
    description = "Attempt a mutation, then add and query the shopapi source"

    setup {
      script = "scripts/task/read_only_by_design/setup.sh"
    }

    check {
      script          = "scripts/task/read_only_by_design/check.sh"
      failure_message = "Either the mutation attempt or the shopapi source is missing - see the instructions for both steps."
    }
  }
}
