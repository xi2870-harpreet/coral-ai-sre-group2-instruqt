resource "page" "meet_the_stack" {
  title = "Meet the Stack You're On Call For"
  file  = "instructions/meet_the_stack.md"

  activities = {
    meet_the_stack = resource.task.meet_the_stack
  }
}

resource "page" "one_sql_connection" {
  title = "One SQL Connection"
  file  = "instructions/one_sql_connection.md"

  activities = {
    one_sql_connection = resource.task.one_sql_connection
  }
}

resource "page" "agent_online" {
  title = "Agent Online"
  file  = "instructions/agent_online.md"

  activities = {
    agent_online = resource.task.agent_online
  }
}

resource "page" "the_incident" {
  title = "Incident: Checkout Is Down"
  file  = "instructions/the_incident.md"

  activities = {
    the_incident = resource.task.the_incident
  }
}

resource "page" "read_only_by_design" {
  title = "Read-Only by Design"
  file  = "instructions/read_only_by_design.md"

  activities = {
    read_only_by_design = resource.task.read_only_by_design
  }
}
