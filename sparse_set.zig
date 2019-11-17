const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const AllowResize = union(enum) {
    Yes,
    No,
};

/// Creates a Sparse Set
/// See https://github.com/Srekel/zig-sparse-set for latest version and documentation
/// Also see the unit tests for usage examples.
pub fn SparseSet(comptime SparseT: type, comptime DenseT: type, comptime allow_resize: AllowResize) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        dense_to_sparse: []SparseT,
        sparse_to_dense: []DenseT,
        dense_count: DenseT,
        capacity_dense: DenseT,
        capacity_sparse: SparseT,

        /// You can think of capacity_sparse as how many entities you want to support, and
        /// capacity_dense as how many components.
        pub fn init(allocator: *Allocator, capacity_sparse: SparseT, capacity_dense: DenseT) !Self {
            // Could be <= but I'm not sure why'd you use a sparse_set if you don't have more sparse
            // indices than dense...
            assert(capacity_dense < capacity_sparse);
            var self = Self{
                .allocator = allocator,
                .dense_to_sparse = try allocator.alloc(SparseT, capacity_dense),
                .sparse_to_dense = try allocator.alloc(DenseT, capacity_sparse),
                .capacity_dense = capacity_dense,
                .capacity_sparse = capacity_sparse,
                .dense_count = 0,
            };

            // Ensure Valgrind doesn't complain
            // std.valgrind.memcheck.makeMemDefined(@ptrCast([*]u8, self.sparse_to_dense.ptr)[0 .. @sizeOf(DenseT) * self.capacity_sparse]);
            return self;
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.dense_to_sparse);
            self.allocator.free(self.sparse_to_dense);
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

        pub fn remainingCapacity(self: Self) DenseT {
            return self.capacity_dense - self.dense_count;
        }

        /// Registers the sparse value and matches it to a dense index
        pub fn add(self: *Self, sparse: SparseT) DenseT {
            if (allow_resize == AllowResize.Yes) {
                if (self.dense_count == self.capacity_dense) {
                    // Possible TODO: Expose growth factor
                    var capacity_dense_new = self.capacity_dense * 2;
                    var dts_new = self.allocator.alloc(SparseT, capacity_dense_new) catch unreachable;
                    std.mem.copy(SparseT, dts_new[0..self.dense_count], self.dense_to_sparse);
                    self.allocator.free(self.dense_to_sparse);
                    self.dense_to_sparse = dts_new;
                    self.capacity_dense = capacity_dense_new;
                }
            }

            assert(sparse < self.capacity_sparse);
            assert(self.dense_count < self.capacity_dense);
            assert(!self.hasSparse(sparse));
            self.dense_to_sparse[self.dense_count] = sparse;
            self.sparse_to_dense[sparse] = self.dense_count;
            self.dense_count += 1;
            return self.dense_count - 1;
        }

        /// May return error.OutOfBounds or error.AlreadyRegistered, otherwise calls add.
        pub fn addOrError(self: *Self, sparse: SparseT) !DenseT {
            if (sparse >= self.capacity_sparse) {
                return error.OutOfBounds;
            }

            if (self.dense_count == self.capacity_dense) {
                return error.OutOfBounds;
            }

            if (try self.hasSparseOrError(sparse)) {
                return error.AlreadyRegistered;
            }

            return self.add(sparse);
        }

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

        /// Like removeWithInfo info, but slightly faster, in case you don't care about the switch,
        /// which you probably *do*, so this should only be used in rare cases.
        pub fn remove(self: *Self, sparse: SparseT) void {
            assert(self.dense_count > 0);
            assert(self.hasSparse(sparse));
            var last_dense = self.dense_count - 1;
            var last_sparse = self.dense_to_sparse[last_dense];
            var dense = self.sparse_to_dense[sparse];
            self.dense_to_sparse[dense] = last_sparse;
            self.sparse_to_dense[last_sparse] = dense;
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
    };
}
