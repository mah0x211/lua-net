# net.scm_rights

defined in [src/scm_rights.c](../src/scm_rights.c).

A userdata queue owning file descriptors received by `net.socket:recvfd()` or
[net.unix.Socket:recvfd()/recvfdsync()](net_unix_socket.md). There is no public
constructor or standalone module to load.

Descriptors are retrieved in receive order. The queue can own any descriptor
type, including regular files and pipes, not just sockets. Garbage collection
closes only unclaimed descriptors.

```lua
local fdq, err, timeout = sock:recvfd()
if fdq then
    local fd = fdq:get() -- caller now owns fd
    -- use fd, then close it
    fdq:close() -- close any remaining descriptors
end
```


## fd = fdq:peek()

Returns the next descriptor without removing it, or nil if the queue is empty
or closed. This is a borrowed descriptor: do not close it or transfer ownership
to another wrapper.


## n = fdq:len()

Returns the number of unclaimed descriptors. An empty or closed queue returns
zero.


## fd = fdq:get()

Removes the next descriptor and transfers ownership to the caller, who must
close it after use. Returns nil if the queue is empty or closed.


## err = fdq:close()

Closes all unclaimed descriptors. Returns nil on success or an error on
failure; still attempts every close. Repeated calls are safe. Descriptors
already retrieved with `get()` are not closed.
