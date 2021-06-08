# tstdb
An efficient Ternary Search Tree and persistent database for LuaJIT

Ternary search trees are a somewhat underrated data structure. This is due, among other things, to the often naïve implementation. Thus, in many cases the following structure is chosen for the nodes (in C): 
```C
typedef struct sNode Node;
struct sNode { char splitchar; char flag; Node *high; Node *low; Node *equal; };
```
On a 64-bit system, each node has a size of 32 bytes. As we will see, this size can be easily halved. Also, in many cases, memory is allocated individually for each node during insertion, which is very inefficient. The solution to both problems is to use an array-based tree where the low/equal/high structure members represent array indices:
```C
typedef struct { char splitchar; char flag; uint32_t high; uint32_t low; uint32_t equal; } Node;
```
This reduces the node size to 16 bytes and we can allocate memory for the array of nodes in advance. With a uint32_t as index, 2^32 nodes can be addressed, which is a lot of memory (64GB), since search trees are very space efficient. A German dictionary with 356008 words and an average word length of 12 bytes requires 780954 nodes = 2.2 nodes per word (and German words can be very long: "Telekommunikationsüberwachungsverordnung". Because of the shared prefixes, if you add the plural "Telekommunikationsüberwachungsverordnung**en**" the word consumes only 2 new nodes).

### Basic usage
```Lua
-- import 
local TSTDB = require("tstdb")

-- create an instance  
local db = TSTDB()

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

### Persistence
To make the tree persistent, a filename can be passed to the constructor:
```Lua
local db, err = TSTDB("fruits.db")
if not db then
    -- your errorhandling here
    print(err)
    return
end
```
When using a persistent tree, it is important to check the return value of the constructor, since various errors can occur when working with files (no write permissions, corrupt database files, etc.). If the file exists, the content is loaded, otherwise it is created. All changes (put, remove, optimize) are written to the file immediately. The database is absolutely fail-safe: even in the event of a power failure or program crash during a write operation, the database is automatically repaired at the next startup. The database format is human readable so that it can be edited with an text editor:
```
TSTDB
7       bananas
6       apples
8       cherries
-6      apples
```
A database file starts with the header "TSTDB" in the first line. Each entry starts with the length (in bytes) of the key, followed by a tab (ASCII 9) and the key. If the length is negative, the following key is removed.

### Optimization
Ternary Search Trees are sensitive to the order of the inserted words: if you insert the keys in sorted order you end up with a long skinny tree. You can check the state of the tree with the state method:
```Lua
print(db.state())
```
This method returns a number between 0 (completely unbalanced) and 1 (completely balanced). The optimize method rebuilds the tree by reinserting all keys in random order:
```Lua
db.optimize()
```
It is also useful to call this method when you have removed many keys. Note that the number of nodes always remains the same, no matter in which order the keys are inserted.
The tree can be displayed using the dump method:
```Lua
local db = TSTDB()
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
### Use as database
Ternary Search Trees are underestimated mainly because they are usually only used as a sorted set. However, they can be used very efficiently as a (simple) database. Let's make a little example (we wan't to store users and groups):
```Lua
local TSTDB = require("tstdb")

local db = TSTDB()
-- insert the first user
db.put("/user/walter/")
db.put("/user/walter/password/secret123")
db.put("/user/walter/group/admin")
-- insert a second user
db.put("/user/jesse/")
db.put("/user/jesse/password/verysecret")
db.put("/user/jesse/group/standard")
```
The character '/' as path separator has (for now) no special meaning for the TST - you can use any char.
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
Which gives us all the results in alphabetical order:  
```
/user/jesse/  
/user/walter/
```
If not the whole key but only the username is to be queried, the search method can be called with a third parameter that selects the segment of the key:
```Lua
db.search("/user/*/", print, 2)
```
Output:
```
jesse  
walter
```
This only works if you use the character '/' as separator (so the slash has a special meaning after all - at least for the search method).

Another query: Count all users in the "admin" group:
```Lua
local count = 0
db.search("/user/*/group/admin", function() count = count + 1 end)
print(count)
```
