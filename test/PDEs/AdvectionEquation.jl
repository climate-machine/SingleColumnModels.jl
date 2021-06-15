adv_eq_dir = joinpath(output_root, "AdvectionEquation")

print_norms = false

plot_solution(grid, aux, wave_speed, filename) = nothing
plot_solution_burgers(grid, aux, velocity_sign, filename) = nothing

using Requires
@init @require Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80" begin
    using .Plots

    function plot_solution(grid, aux, wave_speed, filename)
        mkpath(dirname(filename))
        domain_range = over_elems_real(grid)
        x = [grid.zc[k] for k in domain_range]
        if wave_speed == -1
            y = [aux[:ϕ_initial, k] for k in domain_range]
            plot(
                y,
                x,
                label = "initial",
                markercolor = "blue",
                linecolor = "blue",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [q[:ϕ, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "numerical",
                markercolor = "black",
                linecolor = "black",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [aux[:ϕ_error, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "error",
                markercolor = "red",
                linecolor = "red",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [aux[:ϕ_analytic, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "analytic",
                markercolor = "green",
                linecolor = "green",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
        else
            y = [q[:ϕ, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "",
                markercolor = "black",
                linecolor = "black",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [aux[:ϕ_error, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "",
                markercolor = "red",
                linecolor = "red",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [aux[:ϕ_analytic, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "",
                markercolor = "green",
                linecolor = "green",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
        end
        wave_speed == 1 && savefig(filename)
    end

    function plot_solution_burgers(grid, aux, velocity_sign, filename)
        mkpath(dirname(filename))
        domain_range = over_elems_real(grid)
        x = [grid.zc[k] for k in domain_range]
        if velocity_sign == -1
            y = [aux[:w_initial, k] for k in domain_range]
            plot(
                y,
                x,
                label = "initial",
                markercolor = "blue",
                linecolor = "blue",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [q[:w, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "numerical",
                markercolor = "black",
                linecolor = "black",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
        else
            y = [aux[:w_initial, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "",
                markercolor = "blue",
                linecolor = "blue",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
            y = [q[:w, k] for k in domain_range]
            plot!(
                y,
                x,
                label = "",
                markercolor = "black",
                linecolor = "black",
                markershapes = markershape,
                markersize = 2,
                legend = :topleft,
            )
        end
        velocity_sign == 1 && savefig(joinpath(directory, name))
    end

end

@testset "Linear advection, ∂_t ϕ + ∇•(cϕ) = 0 ∈ ∂Ω, ϕ(t=0) = Gaussian(σ, μ), ConservativeForm, explicit Euler" begin
    domain_set = DomainSet(gm = 1)
    domain_subset = DomainSubSet(gm = true)
    σ, μ = 0.1, 0.5
    δz = 0.2
    Triangle(z) = μ - δz < z < μ + δz ?
        (μ > z ? (z - (μ - δz)) / δz : ((μ + δz) - z) / δz) : 0.0
    Square(z) = μ - δz < z < μ + δz ? 1 : 0.0
    Gaussian(z) = exp(-1 / 2 * ((z - μ) / σ)^2)
    for n_elems_real in (64, 128)
        grid = UniformGrid(0.0, 1.0, n_elems_real)
        domain_range = over_elems_real(grid)
        x = [grid.zc[k] for k in domain_range]
        unknowns = ((:ϕ, domain_subset),)
        vars = (
            (:ϕ_initial, domain_subset),
            (:ϕ_error, domain_subset),
            (:ϕ_analytic, domain_subset),
        )
        n_points = length(over_elems(grid))
        FT = eltype(grid)
        q = StateVec(unknowns, FT, n_points, domain_set)
        aux = StateVec(vars, FT, n_points, domain_set)
        rhs = deepcopy(q)
        CFL = 0.1
        Δt = CFL * grid.Δz
        T = 0.25
        maxiter = Int(T / Δt)
        for scheme in
            (UpwindAdvective(), UpwindCollocated(), CenteredUnstable())
            for distribution in (Triangle, Square, Gaussian)
                for wave_speed in (-1, 1)
                    scheme_name = replace(string(scheme), "()" => "")
                    distribution_name =
                        joinpath("LinearAdvection", string(distribution))
                    directory =
                        joinpath(adv_eq_dir, distribution_name, scheme_name)
                    print_norms && print(
                        "\n",
                        directory,
                        ", ",
                        n_elems_real,
                        ", ",
                        wave_speed,
                        ", ",
                    )

                    for k in over_elems_real(grid)
                        aux[:ϕ_initial, k] = distribution(grid.zc[k])
                        q[:ϕ, k] = aux[:ϕ_initial, k]
                    end
                    amax_w = max([
                        max(aux[:ϕ_initial, k]) for k in over_elems_real(grid)
                    ]...)
                    for i in 1:maxiter
                        for k in over_elems_real(grid)
                            ϕ = q[:ϕ, Cut(k)]
                            ϕ_dual = q[:ϕ, Dual(k)]
                            w = [wave_speed, wave_speed, wave_speed]
                            w_dual = [wave_speed, wave_speed]
                            rhs[:ϕ, k] =
                                -advect_old(
                                    ϕ,
                                    ϕ_dual,
                                    w,
                                    w_dual,
                                    grid,
                                    scheme,
                                    Δt,
                                )
                        end
                        for k in over_elems(grid)
                            q[:ϕ, k] += Δt * rhs[:ϕ, k]
                        end
                        apply_Dirichlet!(q, :ϕ, grid, 0.0, Zmax())
                        apply_Dirichlet!(q, :ϕ, grid, 0.0, Zmin())
                    end
                    sol_analtyic = [
                        distribution(grid.zc[k] - wave_speed * T)
                        for k in over_elems(grid)
                    ]
                    sol_error =
                        [sol_analtyic[k] - q[:ϕ, k] for k in over_elems(grid)]
                    L2_norm = sum(sol_error .^ 2) / length(sol_error)

                    if !(scheme == CenteredUnstable())
                        @test all(abs.(sol_error) .< 100 * grid.Δz)
                        @test all(L2_norm < 100 * grid.Δz)
                    end
                    for k in over_elems(grid)
                        aux[:ϕ_error, k] = sol_error[k]
                        aux[:ϕ_analytic, k] = sol_analtyic[k]
                    end

                    print_norms && print("L2_norm(err) = ", L2_norm)

                    name = string(n_elems_real)
                    markershape = wave_speed == -1 ? :dtriangle : :utriangle
                    # Skip plotting...
                    # plot_solution(
                    #     grid,
                    #     aux,
                    #     wave_speed,
                    #     joinpath(directory, name),
                    # )
                end
            end
        end
    end
end

@testset "Non-linear Bergers, ∂_t w + ∇•(ww) = 0 ∈ ∂Ω, u(t=0) = Gaussian(σ, μ), ConservativeForm, explicit Euler" begin
    domain_set = DomainSet(gm = 1)
    domain_subset = DomainSubSet(gm = true)
    σ, μ = 0.1, 0.5
    δz = 0.2
    Triangle(z, velocity_sign) = μ - δz < z < μ + δz ?
        (
        μ > z ? velocity_sign * (z - (μ - δz)) / δz :
            velocity_sign * ((μ + δz) - z) / δz
    ) :
        0.0
    Square(z, velocity_sign) = μ - δz < z < μ + δz ? velocity_sign : 0.0
    Gaussian(z, velocity_sign) = velocity_sign * exp(-1 / 2 * ((z - μ) / σ)^2)
    for n_elems_real in (64, 128)
        grid = UniformGrid(0.0, 1.0, n_elems_real)
        domain_range = over_elems_real(grid)
        x = [grid.zc[k] for k in domain_range]
        unknowns = ((:w, domain_subset),)
        vars = (
            (:w_initial, domain_subset),
            (:w_error, domain_subset),
            (:w_analytic, domain_subset),
        )
        n_points = length(over_elems(grid))
        FT = eltype(grid)
        q = StateVec(unknowns, FT, n_points, domain_set)
        aux = StateVec(vars, FT, n_points, domain_set)
        rhs = deepcopy(q)
        CFL = 0.1
        Δt = CFL * grid.Δz
        T = 0.25
        maxiter = Int(T / Δt)
        for scheme in
            (UpwindAdvective(), UpwindCollocated(), CenteredUnstable())
            for distribution in (Triangle, Square, Gaussian)
                for velocity_sign in (-1, 1)
                    for k in over_elems_real(grid)
                        aux[:w_initial, k] =
                            distribution(grid.zc[k], velocity_sign)
                        q[:w, k] = aux[:w_initial, k]
                    end
                    amax_w = max([
                        max(aux[:w_initial, k]) for k in over_elems_real(grid)
                    ]...)
                    for i in 1:maxiter
                        for k in over_elems_real(grid)
                            w = q[:w, Cut(k)]
                            w_dual = (w[1:2] + w[2:3]) / 2
                            rhs[:w, k] =
                                -advect_old(
                                    w,
                                    w_dual,
                                    w,
                                    w_dual,
                                    grid,
                                    scheme,
                                    Δt,
                                )
                        end
                        for k in over_elems(grid)
                            q[:w, k] += Δt * rhs[:w, k]
                        end
                        apply_Dirichlet!(q, :w, grid, 0.0, Zmax())
                        apply_Dirichlet!(q, :w, grid, 0.0, Zmin())
                    end

                    scheme_name = replace(string(scheme), "()" => "")
                    distribution_name =
                        joinpath("BurgersEquation", string(distribution))
                    directory =
                        joinpath(adv_eq_dir, distribution_name, scheme_name)
                    name = string(n_elems_real)
                    markershape = velocity_sign == -1 ? :dtriangle : :utriangle
                    plot_solution_burgers(
                        grid,
                        aux,
                        velocity_sign,
                        joinpath(directory, name),
                    )
                end
            end
        end
    end

end
