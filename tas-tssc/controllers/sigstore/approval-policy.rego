package sigstore
    
default isCompliant = false

isCompliant {
    # Check that release is approved
    input.predicate.release.approved == true
    
    # Check that serviceNowTickets array exists and has at least one entry
    count(input.predicate.serviceNowTickets) > 0
    
    # Check that all tickets have valid status for their type
    not any_invalid_ticket_status
}

# Helper rule: checks if ANY ticket has an invalid status
any_invalid_ticket_status {
    ticket := input.predicate.serviceNowTickets[_]
    not valid_ticket_status(ticket)
}

# Helper rule: validates ticket status based on type
valid_ticket_status(ticket) {
    ticket.type == "Change Request"
    ticket.status == "Approved"
}

valid_ticket_status(ticket) {
    ticket.type == "Requested Item"
    ticket.status == "Closed Complete"
}