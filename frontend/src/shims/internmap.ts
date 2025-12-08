// Minimal shims for internmap used by d3-array; suitable for dev builds.
// For production, rely on proper npm packaging of internmap.
export class InternSet<T> extends Set<T> {}
export class InternMap<K, V> extends Map<K, V> {}

