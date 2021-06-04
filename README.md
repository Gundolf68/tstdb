# tstdb
An efficient Ternary Search Tree (and micro-database) for LuaJIT

Ternary search trees are a somewhat underrated data structure. Among other things, this is due to the mostly naive implementation. Thus, in many cases the following structure is chosen for the nodes: 
```C
typedef struct { char splitchar; Node *high; Node *low; Node *equal; } Node;
```
