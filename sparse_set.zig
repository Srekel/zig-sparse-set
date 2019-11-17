const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const AllowResize = union(enum) {
    Yes,
    No,
};

pub const ValueLayout = union(enum) {
    InternalArrayOfStructs,
    ExternalStructOfArraysSupport,
};

pub const SparseSetConfig = struct {
    /// The type used for the sparse handle
    SparseT: type,

    /// The type used for dense indices
    DenseT: type,

    /// Optional: The type use for values when using InternalArrayOfStructs
    ValueT: type = void,

    /// Set this based on if your values are AOS/SOA internally/externally
    value_layout: ValueLayout,

    /// Whether or not the amount of dense indices (and values) can grow
    allow_resize: AllowResize = .No,

    /// Set to true to make values created with add() be zero initialized
    zeroed_values: bool = false,
};

/// Creates a Sparse Set
/// See https://github.com/Srekel/zig-sparse-set for latest version and documentation
/// Also see the unit tests for usage examples.
pub fn SparseSet(comptime config: SparseSetConfig) type {
    comptime const SparseT = config.SparseT;
    comptime const DenseT = config.DenseT;
    comptime const ValueT = config.ValueT;
    comptime const allow_resize = config.allow_resize;
    comptime const value_layout = config.value_layout;
    comptime const zeroed_values = config.zeroed_values;

    return struct {
        const Self = @This();

        allocator: *Allocator,
        dense_to_sparse: []SparseT,
        sparse_to_dense: []DenseT,
        values: if (value_layout == .InternalArrayOfStructs) []ValueT else void,
        dense_count: DenseT,
        capacity_dense: DenseT,
        capacity_sparse: SparseT,

        /// You can think of capacity_sparse as how many entities you want to support, and
        /// capacity_dense as how many components.
        pub fn init(allocator: *Allocator, capacity_sparse: SparseT, capacity_dense: DenseT) !Self {
            // Could be <= but I'm not sure why'd you use a sparse_set if you don't have more sparse
            // indices than dense...
            assert(capacity_dense < capacity_sparse);
            var self: Self = undefined;
            if (value_layout == .InternalArrayOfStructs) {
                self = Self{
                    .allocator = allocator,
                    .dense_to_sparse = try allocator.alloc(SparseT, capacity_dense),
                    .sparse_to_dense = try allocator.alloc(DenseT, capacity_sparse),
                    .values = try allocator.alloc(ValueT, capacity_dense),
                    .capacity_dense = capacity_dense,
                    .capacity_sparse = capacity_sparse,
                    .dense_count = 0,
                };
            } else {
                self = Self{
                    .allocator = allocator,
                    .dense_to_sparse = try allocator.alloc(SparseT, capacity_dense),
                    .sparse_to_dense = try allocator.alloc(DenseT, capacity_sparse),
                    .values = {},
                    .capacity_dense = capacity_dense,
                    .capacity_sparse = capacity_sparse,
                    .dense_count = 0,
                };
            }

            // Ensure Valgrind doesn't complain
            // std.valgrind.memcheck.makeMemDefined(std.mem.asBytes(&self.sparse_to_dense));

            return self;
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.dense_to_sparse);
            self.allocator.free(self.sparse_to_dense);
            if (value_layout == .InternalArrayOfStructs) {
                self.allocator.free(self.values);
            }
        }

        pub fn clear(self: *Self) void {
            self.dense_count = 0;
        }

        pub fn len(self: Self) void {
            return self.dense_count;
        }

        pub fn toSparseSlice(self: Self) []SparseT {
            return self.dense_to_sparse[0..self.dense_count];
        }

        // A bit of a hack to comptime add a function
        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                pub fn toValueSlice(self: Self) []ValueT {
                    return self.values[0..self.dense_count];
                }
            },
            else => struct {},
        };

        /// Returns how many dense indices are still available
        pub fn remainingCapacity(self: Self) DenseT {
            return self.capacity_dense - self.dense_count;
        }

        /// Registers the sparse value and matches it to a dense index
        /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
        /// Note: If resizing is allowed, you must use an allocator that you are sure
        /// will never fail for your use cases.
        ///  If that is not an option, use addOrError.
        pub fn add(self: *Self, sparse: SparseT) DenseT {
            if (allow_resize == .Yes) {
                if (self.dense_count == self.capacity_dense) {
                    self.capacity_dense = self.capacity_dense * 2;
                    self.dense_to_sparse = self.allocator.realloc(self.dense_to_sparse, self.capacity_dense) catch unreachable;
                    if (value_layout == .InternalArrayOfStructs) {
                        self.values = self.allocator.realloc(self.values, self.capacity_dense) catch unreachable;
                    }
                }
            }

            assert(sparse < self.capacity_sparse);
            assert(self.dense_count < self.capacity_dense);
            assert(!self.hasSparse(sparse));
            self.dense_to_sparse[self.dense_count] = sparse;
            self.sparse_to_dense[sparse] = self.dense_count;
            if (value_layout == .InternalArrayOfStructs and zeroed_values) {
                std.mem.set(u8, std.mem.asBytes(&self.values[self.dense_count]), 0);
            }

            self.dense_count += 1;
            return self.dense_count - 1;
        }

        /// May return error.OutOfBounds or error.AlreadyRegistered, otherwise calls add.
        /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
        pub fn addOrError(self: *Self, sparse: SparseT) !DenseT {
            if (sparse >= self.capacity_sparse) {
                return error.OutOfBounds;
            }

            if (try self.hasSparseOrError(sparse)) {
                return error.AlreadyRegistered;
            }

            if (self.dense_count == self.capacity_dense) {
                if (allow_resize == .Yes) {
                    self.capacity_dense = self.capacity_dense * 2;
                    self.dense_to_sparse = try self.allocator.realloc(self.dense_to_sparse, self.capacity_dense);
                    if (value_layout == .InternalArrayOfStructs) {
                        self.values = try self.allocator.realloc(self.values, self.capacity_dense);
                    }
                } else {
                    return error.OutOfBounds;
                }
            }

            return self.add(sparse);
        }

        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                /// Registers the sparse value and matches it to a dense index
                /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
                /// Note: If resizing is allowed, you must use an allocator that you are sure
                /// will never fail for your use cases.
                ///  If that is not an option, use addOrError.
                pub fn addValue(self: *Self, sparse: SparseT, value: ValueT) DenseT {
                    if (allow_resize == .Yes) {
                        if (self.dense_count == self.capacity_dense) {
                            self.capacity_dense = self.capacity_dense * 2;
                            self.dense_to_sparse = self.allocator.realloc(self.dense_to_sparse, self.capacity_dense) catch unreachable;
                            if (value_layout == .InternalArrayOfStructs) {
                                self.values = self.allocator.realloc(self.values, self.capacity_dense) catch unreachable;
                            }
                        }
                    }

                    assert(sparse < self.capacity_sparse);
                    assert(self.dense_count < self.capacity_dense);
                    assert(!self.hasSparse(sparse));
                    self.dense_to_sparse[self.dense_count] = sparse;
                    self.sparse_to_dense[sparse] = self.dense_count;
                    self.values[self.dense_count] = value;
                    self.dense_count += 1;
                    return self.dense_count - 1;
                }

                /// May return error.OutOfBounds or error.AlreadyRegistered, otherwise calls add.
                /// Grows .dense_to_sparse and .values if needed and resizing is allowed.
                pub fn addValueOrError(self: *Self, sparse: SparseT, value: ValueT) !DenseT {
                    if (sparse >= self.capacity_sparse) {
                        return error.OutOfBounds;
                    }

                    if (try self.hasSparseOrError(sparse)) {
                        return error.AlreadyRegistered;
                    }

                    if (self.dense_count == self.capacity_dense) {
                        if (allow_resize == .Yes) {
                            self.capacity_dense = self.capacity_dense * 2;
                            self.dense_to_sparse = try self.allocator.realloc(self.dense_to_sparse, self.capacity_dense);
                            if (value_layout == .InternalArrayOfStructs) {
                                self.values = try self.allocator.realloc(self.values, self.capacity_dense);
                            }
                        } else {
                            return error.OutOfBounds;
                        }
                    }

                    return self.addValue(sparse, value);
                }
            },
            else => struct {},
        };

        /// Removes the sparse/dense index, and replaces it with the last ones.
        /// dense_old and dense_new is
        pub fn removeWithInfo(self: *Self, sparse: SparseT, dense_old: *DenseT, dense_new: *DenseT) void {
            assert(self.dense_count > 0);
            assert(self.hasSparse(sparse));
            var last_dense = self.dense_count - 1;
            var last_sparse = self.dense_to_sparse[last_dense];
            var dense = self.sparse_to_dense[sparse];
            self.dense_to_sparse[dense] = last_sparse;
            self.sparse_to_dense[last_sparse] = dense;
            if (value_layout == .InternalArrayOfStructs) {
                self.values[dense] = self.values[last_dense];
            }

            self.dense_count -= 1;
            dense_old.* = last_dense;
            dense_new.* = dense;
        }

        /// May return error.OutOfBounds, otherwise alls removeWithInfo
        pub fn removeWithInfoOrError(self: *Self, sparse: SparseT, dense_old: *DenseT, dense_new: *DenseT) !void {
            if (self.dense_count == 0) {
                return error.OutOfBounds;
            }

            if (!try self.hasSparseOrError(sparse)) {
                return error.NotRegistered;
            }

            return self.removeWithInfo(sparse, dense_old, dense_new);
        }

        /// Like removeWithInfo info, but slightly faster, in case you don't care about the switch
        pub fn remove(self: *Self, sparse: SparseT) void {
            assert(self.dense_count > 0);
            assert(self.hasSparse(sparse));
            var last_dense = self.dense_count - 1;
            var last_sparse = self.dense_to_sparse[last_dense];
            var dense = self.sparse_to_dense[sparse];
            self.dense_to_sparse[dense] = last_sparse;
            self.sparse_to_dense[last_sparse] = dense;
            if (value_layout == .InternalArrayOfStructs) {
                self.values[dense] = self.values[last_dense];
            }

            self.dense_count -= 1;
        }

        /// May return error.OutOfBounds or error.NotRegistered, otherwise calls self.remove
        pub fn removeOrError(self: *Self, sparse: SparseT) !void {
            if (self.dense_count == 0) {
                return error.OutOfBounds;
            }

            if (!try self.hasSparseOrError(sparse)) {
                return error.NotRegistered;
            }

            self.remove(sparse);
        }

        /// Returns true if the sparse is registered to a dense index
        pub fn hasSparse(self: Self, sparse: SparseT) bool {
            // Unsure if this call to disable runtime safety is needed - can add later if so.
            // @setRuntimeSafety(false);
            assert(sparse < self.capacity_sparse);
            var dense = self.sparse_to_dense[sparse];
            return dense < self.dense_count and self.dense_to_sparse[dense] == sparse;
        }

        /// May return error.OutOfBounds, otherwise calls hasSparse
        pub fn hasSparseOrError(self: Self, sparse: SparseT) !bool {
            if (sparse >= self.capacity_sparse) {
                return error.OutOfBounds;
            }

            return self.hasSparse(sparse);
        }

        /// Returns corresponding dense index
        pub fn getBySparse(self: Self, sparse: SparseT) DenseT {
            assert(self.hasSparse(sparse));
            return self.sparse_to_dense[sparse];
        }

        /// Tries hasSparseOrError, then returns getBySparse
        pub fn getBySparseOrError(self: Self, sparse: SparseT) !DenseT {
            _ = try self.hasSparseOrError(sparse);
            return self.getBySparse(sparse);
        }

        /// Returns corresponding sparse index
        pub fn getByDense(self: Self, dense: DenseT) SparseT {
            assert(dense < self.dense_count);
            return self.dense_to_sparse[dense];
        }

        /// Returns OutOfBounds or getByDense
        pub fn getByDenseOrError(self: Self, dense: DenseT) !SparseT {
            if (dense >= self.dense_count) {
                return error.OutOfBounds;
            }
            return self.getByDense(dense);
        }

        // TODO: Rewrite after https://github.com/ziglang/zig/issues/1717
        pub usingnamespace switch (value_layout) {
            .InternalArrayOfStructs => struct {
                /// Returns a pointer to the SOA value corresponding to the sparse parameter.
                pub fn getValueBySparse(self: Self, sparse: SparseT) *ValueT {
                    assert(self.hasSparse(sparse));
                    var dense = self.sparse_to_dense[sparse];
                    return &self.values[dense];
                }

                // First tries hasSparse, then returns getValueBySparse()
                pub fn getValueBySparseOrError(self: Self, sparse: SparseT) !*ValueT {
                    _ = try self.hasSparseOrError(sparse);
                    return getValueBySparse();
                }

                /// Returns a pointer to the SOA value corresponding to the sparse parameter.
                pub fn getValueByDense(self: Self, dense: DenseT) *ValueT {
                    assert(dense < self.dense_count);
                    return &self.values[dense];
                }

                // Returns error.OutOfBounds or getValueByDense()
                pub fn getValueByDenseOrError(self: Self, dense: DenseT) !*ValueT {
                    if (dense >= self.dense_count) {
                        return error.OutOfBounds;
                    }
                    return getValueByDense();
                }
            },
            else => struct {},
        };
    };
}
