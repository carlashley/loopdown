import os


def max_workers_for_threads(*, max_cap: int = 16, def_cpu_count: int = 4, def_max_threads: int = 4) -> int:
    """Compute a conservative worker limit for thread-based concurrency.
    This is intended for IO-bound workloads where Python threads frequently block (file system access, parsing,
    network IO). The worker count scales with the number of logical CPUs but is capped to avoid excessive
    oversubscription.
    :param max_cap: hard upper limit on the number of worker threads
    :param def_cpu_count: fallback CPU count if the OS cannot determine it
    :param def_max_threads: heuristic multiplier representing the maximum number of concurrent Python workers
                            per logical CPU"""
    return min(max_cap, (os.cpu_count() or def_cpu_count) * def_max_threads)
