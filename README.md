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

Ternary Search Trees are very space efficient. A German dictionary with 356008 words needs 780954 nodes = 2.2 nodes per word (and German words can be very long: "Telekommunikationsüberwachungsverordnung" 😀).

### Basic usage
```Lua
-- import 
local tstdb = require("tstdb")

-- create an instance  
local db = tstdb()

-- insert some keys
db.put("bananas")
db.put("apples")
db.put("cherries")

-- check if a key exists
if db.get("apples") then print("apples!") end

-- print all keys in sorted order
db.keys(function(key) print(key) end)

-- shorter version:
db.keys(print)

-- print all keys in descending order
db.keys(print, true)

-- search for keys with a pattern
db.search("ba*", function(key) print(key) end)

-- search for keys with a more challenging pattern
db.search("*rr*s", print)

-- remove a key
db.remove("apples")

-- print the number of keys
print(db.key_count())

-- print the number of nodes
print(db.node_count())
```
The put method returns a boolean value indicating whether the key was added (true) or already present (false). The same is true for the remove method.

### Optimization
Ternary Search Trees are sensitive to the order of the inserted words: if you insert the keys in sorted order you end up with a long skinny tree. You can check the state of the tree with the state method:
```Lua
print(db.state())
```
This method returns a number between 0 (completely unbalanced) and 1 (completely balanced). 
The tree can be displayed using the dump method:
```Lua
local db = tstdb()
db.put("banana")
db.put("apples")
db.put("bananas")
db.dump()
```
Output:
```
node	char	low	equal	high	flag
1	'b'	7	2	0	0
2	'a'	0	3	0	0
3	'n'	0	4	0	0
4	'a'	0	5	0	0
5	'n'	0	6	0	0
6	'a'	0	13	0	1
7	'a'	0	8	0	0
8	'p'	0	9	0	0
9	'p'	0	10	0	0
10	'l'	0	11	0	0
11	'e'	0	12	0	0
12	's'	0	0	0	1
13	's'	0	0	0	1
```
The optimize method rebuilds the tree by reinserting all keys in random order:
```Lua
db.optimize()
```
It is also useful to call this method when you have removed many keys. Note that the number of nodes always remains the same, no matter in which order the keys are inserted.

### Use as database
They are also underestimated because they are usually only used as a data set from which the keys are retrieved in sorted order. Yet they can be used very efficiently as a database. Let's make a little example (we wan't to store users and groups):
```Lua
local tstdb = require("tstdb")

local db = tstdb()
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
