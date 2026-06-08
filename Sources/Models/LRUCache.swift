struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                set(newValue, for: key)
            } else {
                removeValue(for: key)
            }
        }
    }

    mutating func set(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        if storage.count > limit, let evicted = accessOrder.first {
            accessOrder.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    mutating func value(for key: Key) -> Value? {
        guard let v = storage[key] else { return nil }
        touch(key)
        return v
    }

    @discardableResult
    mutating func removeValue(for key: Key) -> Value? {
        accessOrder.removeAll { $0 == key }
        return storage.removeValue(forKey: key)
    }

    mutating func removeAll() {
        storage.removeAll()
        accessOrder.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
    }
}
