// Author: Karac V. Thweatt
//
// physics_demo.fx - Physics engine demonstration
//
// Simulates:
//   - A sphere falling under gravity onto a ground plane
//   - Two spheres colliding mid-air
//   - A box resting on a plane
//   - Impulse kick applied to a body
//

#import "standard.fx";
#import "physics.fx";

using standard::io::console;
using standard::vectors;
using physics;

def main() -> int
{
    PhysWorld world;
    i32 ground, ball_a, ball_b, box_a;
    i32 step, i;
    RigidBody* b;

    // -------------------------------------------------------------------------
    // Initialise world: up to 64 bodies, 256 contacts
    // -------------------------------------------------------------------------
    world_init(@world, 64, 256);
    world_set_gravity(@world, vec3(0.0, -9.81, 0.0));

    // Ground plane  (normal = +Y, dist = 0  =>  y == 0 surface)
    ground = world_add_plane(@world, vec3(0.0, 1.0, 0.0), 0.0);
    world_set_material(@world, ground, 0.4, 0.6);

    // Ball A: starts at y=10, will fall and bounce off ground
    ball_a = world_add_sphere(@world, vec3(0.0, 10.0, 0.0), 0.5, 1.0);
    world_set_material(@world, ball_a, 0.7, 0.4);

    // Ball B: starts at y=5, slightly offset — will collide with ball A on the way down
    ball_b = world_add_sphere(@world, vec3(0.1, 5.0, 0.0), 0.5, 1.0);
    world_set_material(@world, ball_b, 0.7, 0.4);

    // Box: starts at y=3, half-extents 0.5 on all axes, mass 2 kg
    box_a = world_add_aabb(@world, vec3(3.0, 3.0, 0.0), vec3(0.5, 0.5, 0.5), 2.0);
    world_set_material(@world, box_a, 0.2, 0.7);

    // Kick ball A sideways at t=0
    world_apply_impulse_at(@world, ball_a, vec3(2.0, 0.0, 0.0), vec3(0.0, 10.0, 0.0));

    // -------------------------------------------------------------------------
    // Simulation loop: 120 steps at dt=1/60  (~2 seconds)
    // -------------------------------------------------------------------------
    print("=== Flux Physics Engine Demo ===\n\0");
    print("dt=1/60s, solver_iters=8, 120 steps\n\n\0");

    for (step = 0; step < 120; step++)
    {
        world_step(@world, 0.01666, 8);

        // Print every 10 steps
        if (step % 10 == 0)
        {
            print("-- step \0");
            print(step);
            print(" --\n\0");

            b = world_get_body(@world, ball_a);
            print("  ball_a  pos=(\0");
            print(b.position.x, 3);
            print(", \0");
            print(b.position.y, 3);
            print(", \0");
            print(b.position.z, 3);
            print(")  vel=(\0");
            print(b.velocity.x, 3);
            print(", \0");
            print(b.velocity.y, 3);
            print(")\n\0");

            b = world_get_body(@world, ball_b);
            print("  ball_b  pos=(\0");
            print(b.position.x, 3);
            print(", \0");
            print(b.position.y, 3);
            print(", \0");
            print(b.position.z, 3);
            print(")  vel=(\0");
            print(b.velocity.x, 3);
            print(", \0");
            print(b.velocity.y, 3);
            print(")\n\0");

            b = world_get_body(@world, box_a);
            print("  box_a   pos=(\0");
            print(b.position.x, 3);
            print(", \0");
            print(b.position.y, 3);
            print(", \0");
            print(b.position.z, 3);
            print(")\n\0");

            print("  contacts this step: \0");
            print(world.contact_count);
            print("\n\n\0");
        };
    };

    print("=== Done ===\n\0");

    world_destroy(@world);
    return 0;
};
