# :ferris_wheel: zig-sparse-set :ferris_wheel:

An implementation of Sparse Sets for Zig.

## :confused: What is a Sparse Set? :confused:

A Sparse Set is a fairly simple data structure with some properties that make it especially useful for some aspects in game development, but you know... probably interesting for other areas too.

Here's a good introduction: https://research.swtch.com/sparse

Basically, sparse sets solve this problem: You have a bunch of ***sparse*** handles, but you want to loop over the values they represent linearly over memory.

## :point_down: Example :point_down:

Maybe your game has a few hundred **entities** with a certain **component** (specific piece of game data) at any given time. An entity is a 16 bit ID (handle) and the entities containing this component eventually gets spread out randomly over 0..65535 during runtime.

:anguished: In your frame update function, it would be nice to **not** do this... :anguished:

```zig
for (active_entities) |entity| {
    var some_big_component = &self.components[entity];
    some_component.x += 3;
}
```

... because it would waste memory. Or, in the case that the component isn't huge, but it's expensive to instantiate (i.e. you can't just zero-init it, for example), you need to do that 65k times at startup. Additionally, you'll be skipping over swaths of memory, so every access will likely be a cache miss.

:worried: Similarly, you might want to avoid this... :worried:

```zig
for (self.components) |some_component| {
    if (some_component.enabled) {
        some_component.x += 3;
    }
}
```

...because you'll be doing a lot of looping over data that isn't of interest. Also, you need to store a flag for every component. So potentially cache misses for the `+=` operation here too.

(Note that the flag could be implemented as a bitset lookup, for example, which would probably be better, but still have the same underlying problem).

:heart_eyes: With a sparse set, you can always simply loop over the data linearly: :heart_eyes:

```zig
for (self.component_set.toValueSlice()) |*some_component| {
    some_component.x += 3;
}
```

##  :sunglasses: But wait, there's more! :sunglasses:

1) **O(1)** Lookup from sparse to dense, and vice versa.
2) **O(1)** **Has,** **Add**, and **Remove**.
3) **O(1)** **Clear** (remove all elements).
4) **O(d)** iteration (dense list).
5) Elements of sparse and dense lists do not need to be (and are not) initialized upon startup - they are undefined.
6) Supports SoA-style component layout.
7) If you only need mapping to one array of objects, you can use SparseSetAOS for convenience.
8) Can be inspected "easily" in a debugger.
9) Optional error-handling.
10) Even if you don't need to loop over the values, a sparse set is a potential alternative to a hash map.

:star: [1] This is nice and important because you can then do:

```zig
for (self.component_set.toValueSlice()) |*some_component, dense_index| {
    some_component.x += 3;
    var entity = self.component_set.getByDense(dense_index);
    self.some_other_system.doStuffWithEntity(entity, some_component.x, 1234567);
}
```

:star: [2] The O(1) remove is important. It is solved by swapping in the last element into the removed spot. So there's two things to consider there:

1) Is it cheap to copy the data? Like if your component is large or needs some kind of allocation logic on copy.
2) Is it OK that the list of components are **unsorted**? If not, sparse sets are not a good fit.

:star: [6] With the standard SparseSet implementation, it doesn't actually store any data - you have to do that manually. If you want to, you can store it in an SOA - "Structure of Arrays" manner, like so:

(**Note:** For both the following SOA example and the AOS example below, you can look at src/test.zig for the whole example.)

```zig
const Entity = u32;
const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};
const MyPositionSystemSOA = struct {
    component_set: sparse_set.SparseSet(Entity, u8) = undefined,
    xs: [256]f32 = [_]f32{0} ** 256,
    ys: [256]f32 = [_]f32{0} ** 256,
    zs: [256]f32 = [_]f32{0} ** 256,
```

The trick then is to handle the dense indices:

```zig
const MyPositionSystem = struct {
    // ...

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

    pub fn updateComps(self: *Self) void {
        for (self.component_set.toSparseSlice()) |ent, dense| {
            self.xs[dense] += 3;
        }
    }
};
```

:star: [7] With SparseSetAOS, things are simplified for you, and this will probably be the most common use case. It has the same API but has a few additional functions, and also stores an internal list of all the data.

```zig
const MyPositionSystemAOS = struct {
    component_set: sparse_set_aos.SparseSetAOS(Entity, u8, Vec3) = undefined,

    // ...

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
```

:star: [8] Compared to a sparse-handle-as-index lookup, you don't have a long list of "duds" between each valid element. And compared to a hash map, it should be more straightforward to introspect the sparse set's linear list.

:star: [9] All functions that can assert from bad usage (e.g. adding more handles than the capacity, or indexing out of bounds) also has a corresponding "OrError" function that does Zig-style error handling.

## :smiling_imp: Hold up... What's the catch? :smiling_imp:

1) Well, there's the unsorted thing.
2) If you remove things frequently, and/or your objects are expensive to copy, it may outweigh the benefit of having the data continuous in memory.
3) The lookup requires `@sizeOf(DenseT) * MaxSparseValue` bytes. So for the example above, if you know that you will never have more than 256 of a specific component, then you can store the dense index as a `u8`. This would result in you needing `65536 * 1 byte = 64 kilobytes`. If you need more than 256 components, and say only 16k entities, you'd need 32 kilobytes.
    * **Note:** The dense -> sparse lookup is likely significantly smaller: `@sizeof(SparseT) * MaxDenseValue`, so for example `256 * 2 bytes = 512 bytes`.
4) If you don't need to loop over the elements, and are starved for memory, a hash map might be a better option.
5) Compared to looking the value up directly using the sparse handle as an array index, there's an extra indirection.
6) Using uninitialized memory may cause some validators to complain.

So, all in all there are of course benefits and drawbacks to sparse sets. You'll have to consider this on a case-by-case basis.

## :page_with_curl: License :page_with_curl:

Pick your license: Public Domaim (Unlicense) or MIT.

