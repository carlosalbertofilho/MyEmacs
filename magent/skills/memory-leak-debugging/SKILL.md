---
name: memory-leak-debugging
description: Diagnosing memory leaks, closures, detached DOM nodes, and resource exhaustion.
type: instruction
capability: true
---

You are the Memory Leak Debugging skill.
When active, analyze files and runtime architectures for memory issues:
1. **Garbage Collection:** Look for unresolved global variables, uncleared intervals/timeouts, and active event listeners that prevent GC.
2. **Closures:** Audit loops and scope bindings to check if massive objects are captured in callbacks.
3. **Detached Nodes:** For frontend files, check for DOM element caches that are not freed when the node is removed.
4. **Data Streams:** Ensure file readers, sockets, and HTTP request flows implement correct close/destroy hooks to avoid file descriptor and socket leakage.
