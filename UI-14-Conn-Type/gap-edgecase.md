Stale connections Problem: 
fast path
wifi

connection

When two users are chatting and one drops and the other sends a message. the node of User-A will try to find out if we have already a connection, and it will find a stale wone in the fast path. and when it sends the message, the ACK waits for 10s or 15s as a timeout then it will realize it doesn't get an ACK back , so it will send to the inbodx.

