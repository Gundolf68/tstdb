# tstdb
An efficient Ternary Search Tree and persistent micro-database for LuaJIT

Ternary search trees are a somewhat underrated data structure. This is due, among other things, to the often naïve implementation. Thus, in many cases the following structure is chosen for the nodes (in C): 
```C
typedef struct sNode Node;
struct sNode { char splitchar; char flag; Node *high; Node *low; Node *equal; };
```
On a 64-bit system, each node has a size of 32 bytes. As we will see, this size can be easily halved. Also, in many cases, memory is allocated individually for each node during insertion, which is very inefficient.

The solution to both problems is to use an array-based tree with this structure:
```C
typedef struct { char splitchar; char flag; uint32_t high; uint32_t low; uint32_t equal; } Node;
```
Now we have a node size of 16 bytes and can allocate memory for the nodes in advance. With an uint32_t array index we can create a TST with max. 2^32 nodes = 64GB (which is a lot of memory). 

Ternary Search Trees are very space efficient. A German dictionary with 356008 words and a file size of 4.5M needs 780954 nodes = 2.2 nodes per word (and German words can be very long: "Telekommunikationsüberwachungsverordnung" 😀).
  
### Use as database
They are also underestimated because they are usually only used as a data set from which the keys are retrieved in sorted order. Yet they can be used very efficiently as a database. Let's make a little example (we wan't to store users and groups):
```Lua
local TST = require("tst")

local db = TST()
-- insert the first user
db.put("/user/walter/")
db.put("/user/walter/password/secret123")
db.put("/user/walter/group/admin")
-- insert a second user
db.put("/user/jesse/")
db.put("/user/jesse/password/verysecret")
db.put("/user/jesse/group/standard")
```
The char '/' as path separator has no special meaning for the TST - you can use any char.
Now some queries. Suppose a user wants to log in:
```Lua
if db.get("/user/" .. name .. "/password/" .. password) then
    print("login ok")
else
    print("login failed")
end
```
To query all users, we use the search method, which takes a text pattern with one or more wildcards and a callback function as parameters:
```Lua
db.search("/user/*/", function(key) print(key) end)
-- shorter:
db.search("/user/*/", print)
```
Outputs all matching entries in alphabetical order:  
```
/user/jesse/  
/user/walter/
```
