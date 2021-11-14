# net.poll

defined in [net.poll](../lib/poll.lua) module.


## ok = poll.pollable()

determine the availability of the polling mechanism.

**Returns**

- `ok:boolean`: `true` on the polling mechanism is available.


## ok, err, timeout = poll.waitrecv( fd, deadline [, hook [, ctx]] )

wait until the file descriptor is readable.

**Parameters**

- `fd:integer`: a file descriptor.
- `deadline:integer`: specify a timeout milliseconds as unsigned integer.
- `hook:function`: a hook function that calls before polling a status of file descriptor.
- `ctx:any: any value for hook function.

**Returns**

- `ok:boolean`: `true` on readable.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = poll.waitsend( fd, deadline [, hook [, ctx]] )

wait until the file descriptor is writable.

**Parameters**

- `fd:integer`: a file descriptor.
- `deadline:integer`: specify a timeout milliseconds as unsigned integer.
- `hook:function`: a hook function that calls before polling a status of file descriptor.
- `ctx:any: any value for hook function.

**Returns**

- `ok:boolean`: `true` on readable.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## poll.unwaitrecv( fd )

cancel waiting for file descriptor to be readable.

**Parameters**

- `fd:integer`: a file descriptor.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## poll.unwaitsend( fd )

cancel waiting for file descriptor to be writable.


**Parameters**

- `fd:integer`: a file descriptor.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## poll.unwait( fd )

cancels waiting for file descriptor to be readable/writable.

**Parameters**

- `fd:integer`: a file descriptor.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## ok, err, timeout = poll.readlock( fd, deadline )

waits until a read lock is acquired.

**Parameters**

- `fd:integer`: a file descriptor.
- `deadline:integer`: a timeout milliseconds as unsigned integer.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err = poll.readunlock( fd )

releases a read lock.

**Parameters**

- `fd:integer`: a file descriptor.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## ok, err, timeout = poll.writelock( fd, deadline )

waits until a write lock is acquired.

**Parameters**

- `fd:integer`: a file descriptor.
- `deadline:integer`: a timeout milliseconds as unsigned integer.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err = poll.writeunlock( fd )

releases a write lock.

**Parameters**

- `fd:integer`: a file descriptor.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.

