const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const SparseSet = @import("sparse_set.zig").SparseSet;

const Entity = u32;
const DenseT = u8;

const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

const DefaultTestSparseSet = SparseSet(.{
    .SparseT = Entity,
    .DenseT = DenseT,
    .allow_resize = .NoResize,
    .value_layout = .ExternalStructOfArraysSupport,
});

const ResizableDefaultTestSparseSet = SparseSet(.{
    .SparseT = Entity,
    .DenseT = DenseT,
    .allow_resize = .ResizeAllowed,
    .value_layout = .ExternalStructOfArraysSupport,
});

const DefaultTestAOSSimpleSparseSet = SparseSet(.{
    .SparseT = Entity,
    .DenseT = DenseT,
    .ValueT = i32,
    .allow_resize = .NoResize,
    .value_layout = .InternalArrayOfStructs,
});

const DefaultTestAOSSystemSparseSet = SparseSet(.{
    .SparseT = Entity,
    .DenseT = DenseT,
    .ValueT = Vec3,
    .allow_resize = .NoResize,
    .value_layout = .InternalArrayOfStructs,
});

const DefaultTestAOSVec3ResizableSparseSet = SparseSet(.{
    .SparseT = Entity,
    .DenseT = DenseT,
    .ValueT = Vec3,
    .allow_resize = .ResizeAllowed,
    .value_layout = .InternalArrayOfStructs,
    .value_init = .ZeroInitialized,
});

test "init safe" {
    var ss = DefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.len());
    for (ss.sparse_to_dense, 0..) |dense_undefined, sparse| {
        _ = dense_undefined;
        var usparse = @intCast(Entity, sparse);
        try testing.expect(!(ss.hasSparse(usparse)));
    }
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.len());
    ss.deinit();
}

test "add / remove safe 1" {
    var ss = DefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    for (ss.dense_to_sparse, 0..) |sparse_undefined, sparse| {
        _ = sparse_undefined;
        var usparse = @intCast(Entity, sparse) + 10;
        var dense_new = ss.add(usparse);
        try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, sparse), dense_new);
        try testing.expect(ss.hasSparse(usparse));
        try testing.expectEqual(dense_new, ss.getBySparse(usparse));
        try testing.expectEqual(usparse, ss.getByDense(dense_new));
    }
    try testing.expectError(error.OutOfBounds, ss.addOrError(1));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.remainingCapacity());

    ss.clear();
    try testing.expect(!(ss.hasSparse(1)));
}

test "add / remove safe 2" {
    var ss = DefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    try testing.expect(!(ss.hasSparse(1)));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.add(1));
    try testing.expect(ss.hasSparse(1));
    try testing.expectError(error.AlreadyRegistered, ss.addOrError(1));
    ss.remove(1);
    try testing.expect(!(ss.hasSparse(1)));
}

test "add / remove safe 3" {
    var ss = DefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    for (ss.dense_to_sparse, 0..) |sparse_undefined, sparse| {
        _ = sparse_undefined;
        var usparse = @intCast(Entity, sparse) + 10;
        _ = ss.add(usparse);
    }

    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.remainingCapacity());
    try testing.expect(!(ss.hasSparse(5)));
    try testing.expect(ss.hasSparse(15));
    ss.remove(15);
    try testing.expect(!(ss.hasSparse(15)));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 1), ss.remainingCapacity());
    _ = ss.add(15);
    try testing.expect(ss.hasSparse(15));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.remainingCapacity());
}

test "AOS" {
    var ss = DefaultTestAOSSimpleSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    for (ss.dense_to_sparse, 0..) |sparse_undefined, sparse| {
        _ = sparse_undefined;
        var usparse = @intCast(Entity, sparse) + 10;
        var value = -@intCast(i32, sparse);
        var dense_new = ss.addValue(usparse, value);
        try testing.expectEqual(@intCast(DenseT, sparse), dense_new);
        try testing.expect(ss.hasSparse(usparse));
        try testing.expectEqual(dense_new, ss.getBySparse(usparse));
        try testing.expectEqual(usparse, ss.getByDense(dense_new));
        try testing.expectEqual(value, (ss.getValueByDense(dense_new)).*);
        try testing.expectEqual(value, ss.getValueBySparse(usparse).*);
    }
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 0), ss.remainingCapacity());

    ss.clear();
    try testing.expect(!ss.hasSparse(1));
}

test "AOS system" {
    var sys = MyPositionSystemAOS.init();
    defer sys.deinit();

    var ent1: Entity = 10;
    var ent2: Entity = 20;
    var v1 = Vec3{ .x = 10, .y = 0, .z = 0 };
    var v2 = Vec3{ .x = 20, .y = 0, .z = 0 };
    sys.addComp(ent1, v1);
    sys.addComp(ent2, v2);
    try testing.expectEqual(v1, sys.getComp(ent1));
    try testing.expectEqual(v2, sys.getComp(ent2));
    try testing.expectEqual(v1, sys.component_set.values[0]);
    try testing.expectEqual(v2, sys.component_set.values[1]);
    try testing.expectEqual(@as(DenseT, 0), sys.component_set.getBySparse(ent1));
    try testing.expectEqual(@as(DenseT, 1), sys.component_set.getBySparse(ent2));

    sys.removeComp(ent1);
    try testing.expectEqual(v2, sys.getComp(ent2));
    try testing.expectEqual(v2, sys.component_set.values[0]);
    try testing.expectEqual(@as(DenseT, 0), sys.component_set.getBySparse(ent2));

    sys.updateComps();
    try testing.expectEqual(Vec3{ .x = 23, .y = 0, .z = 0 }, sys.getComp(ent2));
}

test "SOA system" {
    var sys = MyPositionSystemSOA.init();
    defer sys.deinit();

    var ent1: Entity = 10;
    var ent2: Entity = 20;
    var v1 = Vec3{ .x = 10, .y = 0, .z = 0 };
    var v2 = Vec3{ .x = 20, .y = 0, .z = 0 };
    sys.addComp(ent1, v1);
    sys.addComp(ent2, v2);
    try testing.expectEqual(v1, sys.getComp(ent1));
    try testing.expectEqual(v2, sys.getComp(ent2));
    try testing.expectEqual(@as(DenseT, 0), sys.component_set.getBySparse(ent1));
    try testing.expectEqual(@as(DenseT, 1), sys.component_set.getBySparse(ent2));

    sys.removeComp(ent1);
    try testing.expectEqual(v2, sys.getComp(ent2));
    try testing.expectEqual(@as(DenseT, 0), sys.component_set.getBySparse(ent2));

    sys.updateComps();
    try testing.expectEqual(Vec3{ .x = 23, .y = 0, .z = 0 }, sys.getComp(ent2));
}

test "SOA resize true" {
    var ss = ResizableDefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    try testing.expectError(error.OutOfBounds, ss.hasSparseOrError(500));

    for (ss.dense_to_sparse, 0..) |sparse_undefined, sparse| {
        _ = sparse_undefined;
        var usparse = @intCast(Entity, sparse) + 10;
        _ = ss.add(usparse);
        try testing.expect(ss.hasSparse(usparse));
    }

    try testing.expect(!ss.hasSparse(18));
    try testing.expectEqual(@intCast(DenseT, 8), ss.add(18));
    try testing.expect(ss.hasSparse(18));
    try testing.expect(!ss.hasSparse(19));
    try testing.expectEqual(@intCast(u32, 16), @intCast(u32, ss.dense_to_sparse.len));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 7), ss.remainingCapacity());
    try testing.expectEqual(@intCast(Entity, 10), ss.dense_to_sparse[0]);
    try testing.expectEqual(@intCast(Entity, 11), ss.dense_to_sparse[1]);
    try testing.expectEqual(@intCast(Entity, 12), ss.dense_to_sparse[2]);
    try testing.expectEqual(@intCast(Entity, 13), ss.dense_to_sparse[3]);
    try testing.expectEqual(@intCast(Entity, 16), ss.dense_to_sparse[6]);
    try testing.expectEqual(@intCast(Entity, 17), ss.dense_to_sparse[7]);
    try testing.expectEqual(@intCast(Entity, 18), ss.dense_to_sparse[8]);

    ss.clear();
    try testing.expect(!(ss.hasSparse(1)));
}

test "AOS resize true" {
    var ss = DefaultTestAOSVec3ResizableSparseSet.init(std.testing.allocator, 128, 8) catch unreachable;
    defer ss.deinit();

    try testing.expectError(error.OutOfBounds, ss.hasSparseOrError(500));

    for (ss.dense_to_sparse, 0..) |sparse_undefined, sparse| {
        _ = sparse_undefined;
        var usparse = @intCast(Entity, sparse) + 10;
        var value = Vec3{ .x = @intToFloat(f32, sparse), .y = 0, .z = 0 };
        _ = ss.addValue(usparse, value);
        try testing.expect(ss.hasSparse(usparse));
        try testing.expectEqual(value, ss.getValueBySparse(usparse).*);
    }

    try testing.expect(!ss.hasSparse(18));
    try testing.expectEqual(@intCast(DenseT, 8), ss.addValue(18, Vec3{ .x = 8, .y = 0, .z = 0 }));
    try testing.expect(ss.hasSparse(18));
    try testing.expect(!ss.hasSparse(19));
    try testing.expectEqual(@intCast(DefaultTestSparseSet.DenseCapacityT, 7), ss.remainingCapacity());
    try testing.expectEqual(Vec3{ .x = 0, .y = 0, .z = 0 }, ss.getValueBySparse(10).*);
    try testing.expectEqual(Vec3{ .x = 1, .y = 0, .z = 0 }, ss.getValueBySparse(11).*);
    try testing.expectEqual(Vec3{ .x = 2, .y = 0, .z = 0 }, ss.getValueBySparse(12).*);
    try testing.expectEqual(Vec3{ .x = 3, .y = 0, .z = 0 }, ss.getValueBySparse(13).*);
    try testing.expectEqual(Vec3{ .x = 4, .y = 0, .z = 0 }, ss.getValueBySparse(14).*);
    try testing.expectEqual(Vec3{ .x = 5, .y = 0, .z = 0 }, ss.getValueBySparse(15).*);
    try testing.expectEqual(Vec3{ .x = 6, .y = 0, .z = 0 }, ss.getValueBySparse(16).*);
    try testing.expectEqual(Vec3{ .x = 7, .y = 0, .z = 0 }, ss.getValueBySparse(17).*);
    try testing.expectEqual(Vec3{ .x = 8, .y = 0, .z = 0 }, ss.getValueBySparse(18).*);

    ss.clear();
    try testing.expect(!(ss.hasSparse(1)));
}

const MyPositionSystemAOS = struct {
    component_set: DefaultTestAOSSystemSparseSet = undefined,
    const Self = @This();

    pub fn init() MyPositionSystemAOS {
        return Self{
            .component_set = DefaultTestAOSSystemSparseSet.init(std.testing.allocator, 128, 8) catch unreachable,
        };
    }

    pub fn deinit(self: *MyPositionSystemAOS) void {
        self.component_set.deinit();
    }

    pub fn addComp(self: *Self, ent: Entity, pos: Vec3) void {
        _ = self.component_set.addValue(ent, pos);
    }

    pub fn removeComp(self: *Self, ent: Entity) void {
        self.component_set.remove(ent);
    }

    pub fn getComp(self: *Self, ent: Entity) Vec3 {
        return self.component_set.getValueBySparse(ent).*;
    }

    pub fn updateComps(self: Self) void {
        for (self.component_set.toValueSlice()) |*value| {
            value.x += 3;
        }
    }
};

const MyPositionSystemSOA = struct {
    component_set: DefaultTestSparseSet = undefined,
    xs: [256]f32 = [_]f32{0} ** 256,
    ys: [256]f32 = [_]f32{0} ** 256,
    zs: [256]f32 = [_]f32{0} ** 256,
    const Self = @This();

    pub fn init() MyPositionSystemSOA {
        return Self{
            .component_set = DefaultTestSparseSet.init(std.testing.allocator, 128, 8) catch unreachable,
        };
    }

    pub fn deinit(self: *MyPositionSystemSOA) void {
        self.component_set.deinit();
    }

    pub fn addComp(self: *Self, ent: Entity, pos: Vec3) void {
        var dense = self.component_set.add(ent);
        self.xs[dense] = pos.x;
        self.ys[dense] = pos.y;
        self.zs[dense] = pos.z;
    }

    pub fn removeComp(self: *Self, ent: Entity) void {
        var dense_old: DenseT = undefined;
        var dense_new: DenseT = undefined;
        self.component_set.removeWithInfo(ent, &dense_old, &dense_new);
        self.xs[dense_new] = self.xs[dense_old];
        self.ys[dense_new] = self.ys[dense_old];
        self.zs[dense_new] = self.zs[dense_old];
    }

    pub fn getComp(self: *Self, ent: Entity) Vec3 {
        var dense = self.component_set.getBySparse(ent);
        return Vec3{ .x = self.xs[dense], .y = self.ys[dense], .z = self.zs[dense] };
    }

    pub fn updateComps(self: *Self) void {
        for (self.component_set.toSparseSlice(), 0..) |ent, dense| {
            _ = ent;
            self.xs[dense] += 3;
        }
    }
};
