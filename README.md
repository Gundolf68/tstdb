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
Now we have a node size of 16 bytes and can allocate memory for the nodes in advance. With an uint32_t array index we can create a TST with max. 2^32 nodes = 64GB (which is a lot of memory: Ternary search trees are very space efficient. A German dictionary with 356008 words needs about 2.2 nodes per word).
  
