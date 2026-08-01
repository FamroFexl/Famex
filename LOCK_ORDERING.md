If you need a thread and a process locked, acquire the thread spinlock, then the process spinlock.

If you need to lock multiple threads, lock them in tid order. A process orders it's threads by tid.

If you need to lock multiple processes, lock them in pid order.