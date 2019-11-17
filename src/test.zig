const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const sparse_set = @import("sparse_set");
const sparse_set_aos = @import("sparse_set_aos");

test "init safe" {
    var ss = sparse_set.SparseSet(u32, u8, sparse_set.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable;
    for (ss.sparse_to_dense) |dense_undefined, sparse| {
        var usparse = @intCast(u32, sparse);
        testing.expect(!(ss.hasSparse(usparse)));
    }
    ss.deinit();
}

test "add / remove safe 1" {
    var ss = sparse_set.SparseSet(u32, u8, sparse_set.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    for (ss.dense_to_sparse) |sparse_undefined, sparse| {
        var usparse = @intCast(u32, sparse) + 10;
        var dense_new = ss.add(usparse);
        testing.expectEqual(@intCast(u8, sparse), dense_new);
        testing.expect(ss.hasSparse(usparse));
        testing.expectEqual(dense_new, ss.getBySparse(usparse));
        testing.expectEqual(usparse, ss.getByDense(dense_new));
    }
    testing.expectError(error.OutOfBounds, ss.addOrError(1));
    testing.expectEqual(@intCast(u8, 0), ss.remainingCapacity());

    ss.clear();
    testing.expect(!(ss.hasSparse(1)));
}

test "add / remove safe 2" {
    var ss = sparse_set.SparseSet(u32, u8, sparse_set.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    testing.expect(!(ss.hasSparse(1)));
    testing.expectEqual(@intCast(u8, 0), ss.add(1));
    testing.expect(ss.hasSparse(1));
    testing.expectError(error.AlreadyRegistered, ss.addOrError(1));
    ss.remove(1);
    testing.expect(!(ss.hasSparse(1)));
}

test "add / remove safe 3" {
    var ss = sparse_set.SparseSet(u32, u8, sparse_set.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    for (ss.dense_to_sparse) |sparse_undefined, sparse| {
        var usparse = @intCast(u32, sparse) + 10;
        _ = ss.add(usparse);
    }

    testing.expectEqual(@intCast(u8, 0), ss.remainingCapacity());
    testing.expect(!(ss.hasSparse(5)));
    testing.expect(ss.hasSparse(15));
    ss.remove(15);
    testing.expect(!(ss.hasSparse(15)));
    testing.expectEqual(@intCast(u8, 1), ss.remainingCapacity());
    _ = ss.add(15);
    testing.expect(ss.hasSparse(15));
    testing.expectEqual(@intCast(u8, 0), ss.remainingCapacity());
}

test "AOS" {
    var ss = sparse_set_aos.SparseSetAOS(u32, u8, i32, sparse_set_aos.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    for (ss.dense_to_sparse) |sparse_undefined, sparse| {
        var usparse = @intCast(u32, sparse) + 10;
        var value = -@intCast(i32, sparse);
        var dense_new = ss.add(usparse, value);
        testing.expectEqual(@intCast(u8, sparse), dense_new);
        testing.expect(ss.hasSparse(usparse));
        testing.expectEqual(dense_new, ss.getBySparse(usparse));
        testing.expectEqual(usparse, ss.getByDense(dense_new));
        testing.expectEqual(value, (ss.getValueByDense(dense_new)).*);
        testing.expectEqual(value, ss.getValueBySparse(usparse).*);
    }
    testing.expectEqual(@intCast(u8, 0), ss.remainingCapacity());

    ss.clear();
    testing.expect(!ss.hasSparse(1));
}

const Entity = u32;

const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

test "AOS system" {
    var sys = MyPositionSystemAOS.init();
    defer (sys.deinit());

    var ent1: Entity = 10;
    var ent2: Entity = 20;
    var v1 = Vec3{ .x = 10, .y = 0, .z = 0 };
    var v2 = Vec3{ .x = 20, .y = 0, .z = 0 };
    sys.addComp(ent1, v1);
    sys.addComp(ent2, v2);
    testing.expectEqual(v1, sys.getComp(ent1));
    testing.expectEqual(v2, sys.getComp(ent2));
    testing.expectEqual(v1, sys.component_set.values[0]);
    testing.expectEqual(v2, sys.component_set.values[1]);
    testing.expectEqual(@as(u8, 0), sys.component_set.getBySparse(ent1));
    testing.expectEqual(@as(u8, 1), sys.component_set.getBySparse(ent2));

    sys.removeComp(ent1);
    testing.expectEqual(v2, sys.getComp(ent2));
    testing.expectEqual(v2, sys.component_set.values[0]);
    testing.expectEqual(@as(u8, 0), sys.component_set.getBySparse(ent2));

    sys.updateComps();
    testing.expectEqual(Vec3{ .x = 23, .y = 0, .z = 0 }, sys.getComp(ent2));
}

test "SOA system" {
    var sys = MyPositionSystemSOA.init();
    defer (sys.deinit());

    var ent1: Entity = 10;
    var ent2: Entity = 20;
    var v1 = Vec3{ .x = 10, .y = 0, .z = 0 };
    var v2 = Vec3{ .x = 20, .y = 0, .z = 0 };
    sys.addComp(ent1, v1);
    sys.addComp(ent2, v2);
    testing.expectEqual(v1, sys.getComp(ent1));
    testing.expectEqual(v2, sys.getComp(ent2));
    testing.expectEqual(@as(u8, 0), sys.component_set.getBySparse(ent1));
    testing.expectEqual(@as(u8, 1), sys.component_set.getBySparse(ent2));

    sys.removeComp(ent1);
    testing.expectEqual(v2, sys.getComp(ent2));
    testing.expectEqual(@as(u8, 0), sys.component_set.getBySparse(ent2));

    sys.updateComps();
    testing.expectEqual(Vec3{ .x = 23, .y = 0, .z = 0 }, sys.getComp(ent2));
}

test "SOA resize true" {
    var ss = sparse_set.SparseSet(u32, u8, sparse_set.AllowResize.Yes).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    testing.expectError(error.OutOfBounds, ss.hasSparseOrError(500));

    for (ss.dense_to_sparse) |sparse_undefined, sparse| {
        var usparse = @intCast(u32, sparse) + 10;
        var dense_new = ss.add(usparse);
        testing.expect(ss.hasSparse(usparse));
    }

    testing.expect(!ss.hasSparse(18));
    testing.expectEqual(@intCast(u8, 8), ss.add(18));
    testing.expect(ss.hasSparse(18));
    testing.expect(!ss.hasSparse(19));
    testing.expectEqual(@intCast(u32, 16), @intCast(u32, ss.dense_to_sparse.len));
    testing.expectEqual(@intCast(u8, 7), ss.remainingCapacity());
    testing.expectEqual(@intCast(u32, 10), ss.dense_to_sparse[0]);
    testing.expectEqual(@intCast(u32, 11), ss.dense_to_sparse[1]);
    testing.expectEqual(@intCast(u32, 12), ss.dense_to_sparse[2]);
    testing.expectEqual(@intCast(u32, 13), ss.dense_to_sparse[3]);
    testing.expectEqual(@intCast(u32, 16), ss.dense_to_sparse[6]);
    testing.expectEqual(@intCast(u32, 17), ss.dense_to_sparse[7]);
    testing.expectEqual(@intCast(u32, 18), ss.dense_to_sparse[8]);

    ss.clear();
    testing.expect(!(ss.hasSparse(1)));
}

test "AOS resize true" {
    var ss = sparse_set_aos.SparseSetAOS(u32, u8, Vec3, sparse_set_aos.AllowResize.Yes).init(std.debug.global_allocator, 128, 8) catch unreachable;
    defer (ss.deinit());

    testing.expectError(error.OutOfBounds, ss.hasSparseOrError(500));

    for (ss.dense_to_sparse) |sparse_undefined, sparse| {
        var usparse = @intCast(u32, sparse) + 10;
        var value = Vec3{ .x = @intToFloat(f32, sparse), .y = 0, .z = 0 };
        var dense_new = ss.add(usparse, value);
        testing.expect(ss.hasSparse(usparse));
        testing.expectEqual(value, ss.getValueBySparse(usparse).*);
    }

    testing.expect(!ss.hasSparse(18));
    testing.expectEqual(@intCast(u8, 8), ss.add(18, Vec3{ .x = 8, .y = 0, .z = 0 }));
    testing.expect(ss.hasSparse(18));
    testing.expect(!ss.hasSparse(19));
    testing.expectEqual(@intCast(u8, 7), ss.remainingCapacity());
    testing.expectEqual(Vec3{ .x = 0, .y = 0, .z = 0 }, ss.getValueBySparse(10).*);
    testing.expectEqual(Vec3{ .x = 1, .y = 0, .z = 0 }, ss.getValueBySparse(11).*);
    testing.expectEqual(Vec3{ .x = 2, .y = 0, .z = 0 }, ss.getValueBySparse(12).*);
    testing.expectEqual(Vec3{ .x = 3, .y = 0, .z = 0 }, ss.getValueBySparse(13).*);
    testing.expectEqual(Vec3{ .x = 4, .y = 0, .z = 0 }, ss.getValueBySparse(14).*);
    testing.expectEqual(Vec3{ .x = 5, .y = 0, .z = 0 }, ss.getValueBySparse(15).*);
    testing.expectEqual(Vec3{ .x = 6, .y = 0, .z = 0 }, ss.getValueBySparse(16).*);
    testing.expectEqual(Vec3{ .x = 7, .y = 0, .z = 0 }, ss.getValueBySparse(17).*);
    testing.expectEqual(Vec3{ .x = 8, .y = 0, .z = 0 }, ss.getValueBySparse(18).*);

    ss.clear();
    testing.expect(!(ss.hasSparse(1)));
}

const MyPositionSystemAOS = struct {
    component_set: sparse_set_aos.SparseSetAOS(Entity, u8, Vec3, sparse_set_aos.AllowResize.No) = undefined,
    const Self = @This();

    pub fn init() MyPositionSystemAOS {
        return Self{
            .component_set = sparse_set_aos.SparseSetAOS(Entity, u8, Vec3, sparse_set_aos.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable,
        };
    }

    pub fn deinit(self: *MyPositionSystemAOS) void {
        self.component_set.deinit();
    }

    pub fn addComp(self: *Self, ent: Entity, pos: Vec3) void {
        _ = self.component_set.add(ent, pos);
    }

    pub fn removeComp(self: *Self, ent: Entity) void {
        self.component_set.remove(ent);
    }

    pub fn getComp(self: *Self, ent: Entity) Vec3 {
        return self.component_set.getValueBySparse(ent).*;
    }

    pub fn updateComps(self: Self) void {
        for (self.component_set.toValueSlice()) |*value, dense| {
            value.x += 3;
        }
    }
};

const MyPositionSystemSOA = struct {
    component_set: sparse_set.SparseSet(Entity, u8, sparse_set.AllowResize.No) = undefined,
    xs: [256]f32 = [_]f32{0} ** 256,
    ys: [256]f32 = [_]f32{0} ** 256,
    zs: [256]f32 = [_]f32{0} ** 256,
    const Self = @This();

    pub fn init() MyPositionSystemSOA {
        return Self{
            .component_set = sparse_set.SparseSet(Entity, u8, sparse_set.AllowResize.No).init(std.debug.global_allocator, 128, 8) catch unreachable,
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
        var dense_old: u8 = undefined;
        var dense_new: u8 = undefined;
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
        for (self.component_set.toSparseSlice()) |ent, dense| {
            self.xs[dense] += 3;
        }
    }
};
