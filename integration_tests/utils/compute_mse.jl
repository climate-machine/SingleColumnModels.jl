using Plots
using OrderedCollections
using Test
using NCDatasets
using Dierckx
using PrettyTables
using Printf
using ArtifactWrappers

# Get PyCLES_output dataset folder:
#! format: off
PyCLES_output_dataset = ArtifactWrapper(
    @__DIR__,
    isempty(get(ENV, "CI", "")),
    "PyCLES_output",
    ArtifactFile[
    ArtifactFile(url = "https://caltech.box.com/shared/static/johlutwhohvr66wn38cdo7a6rluvz708.nc", filename = "Rico.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/zraeiftuzlgmykzhppqwrym2upqsiwyb.nc", filename = "Gabls.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/toyvhbwmow3nz5bfa145m5fmcb2qbfuz.nc", filename = "DYCOMS_RF01.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/ivo4751camlph6u3k68ftmb1dl4z7uox.nc", filename = "TRMM_LBA.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/4osqp0jpt4cny8fq2ukimgfnyi787vsy.nc", filename = "ARM_SGP.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/jci8l11qetlioab4cxf5myr1r492prk6.nc", filename = "Bomex.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/pzuu6ii99by2s356ij69v5cb615200jq.nc", filename = "Soares.nc",),
    ArtifactFile(url = "https://caltech.box.com/shared/static/7upt639siyc2umon8gs6qsjiqavof5cq.nc", filename = "Nieuwstadt.nc",),
    ],
)
PyCLES_output_dataset_path = get_data_folder(PyCLES_output_dataset)
#! format: on

include("variable_map.jl")

function compute_mse(
    grid,
    q,
    aux,
    params,
    ds,
    experiment,
    best_mse,
    t_compare,
    plot_dir = nothing,
)
    mse = Dict()
    # TODO: we need to store entire solution to compare. Right now
    # we repeat the last solution along the time axis. In addition,
    # We need at least 4 temporal points for interpolation. So, we half
    # the time-step to double the number of points.
    # time_scm = range(0, params[:t_end], step=params[:Δt][1])
    time_scm = range(0, params[:t_end], step = params[:Δt][1] / 2)
    n_time_points = length(time_scm)

    n_fields = length(q.fields[1].vals)
    n_grid_points = length(q.fields)

    # Ensure domain matches:
    z_les = ds["z_half"][:]
    # z_scm = get_z(grid; rm_dupes = true)
    z_scm = grid.zc
    @info "Z extent for LES vs CLIMA:"
    @show extrema(z_scm)
    @show extrema(z_les)

    time_les = ds["t"][:]

    # Find the nearest matching final time:
    t_cmp = min(time_scm[end], time_les[end])

    # Accidentally running a short simulation
    # could improve MSE. So, let's test that
    # we run for at least t_compare. We should
    # increase this as we can reach higher CFL.
    # @test t_cmp >= t_compare

    # Ensure z_scm and fields are consistent lengths:
    @test length(z_scm) == n_grid_points

    data_scm = Dict()
    dons_cont = Dict()
    scm_variables = []
    computed_mse = []
    table_best_mse = []
    mse_reductions = []
    pycles_variables = []
    data_scales = []
    pycles_weight = []
    for (ftc) in keys(best_mse)

        # TODO: clean this up and generalize
        ftc_str = string(ftc)
        gm, en, ud, sd, al = allcombinations(q)
        is_updraft = occursin("_up", ftc_str)
        is_environment = occursin("_en", ftc_str)
        is_grid_mean = occursin("_gm", ftc_str)
        if is_updraft
            domain_decomp = ud[1]
        elseif is_environment
            domain_decomp = en
        elseif is_grid_mean
            domain_decomp = gm
        else
            error("Bad domain")
        end
        if is_updraft
            ftc_scm = Symbol(replace(ftc_str, "_up" => ""))
        elseif is_environment
            ftc_scm = Symbol(replace(ftc_str, "_en" => ""))
        elseif is_grid_mean
            ftc_scm = Symbol(replace(ftc_str, "_gm" => ""))
        else
            error("Bad domain")
        end

        # Only compare fields defined for var_map
        tup = var_map(ftc)
        tup == nothing && continue

        # Unpack the data
        LES_var = tup[1]
        facts = tup[2]
        push!(scm_variables, ftc)
        push!(pycles_variables, LES_var)
        data_ds = ds.group["profiles"]
        data_les = data_ds[LES_var][:]

        # Scale the data for comparison
        ρ = data_ds["rho"][:]
        a_up = data_ds["updraft_fraction"][:]
        a_en = 1 .- data_ds["updraft_fraction"][:]
        ρa_up = ρ .* a_up
        ρa_en = ρ .* a_en
        ρa = is_updraft ? ρa_up : ρa_en
        if :a in facts && :ρ in facts
            data_les .*= ρa
            push!(pycles_weight, "ρa")
        elseif :ρ in facts
            data_les .*= ρ
            push!(pycles_weight, "ρ")
        else
            push!(pycles_weight, "1")
        end

        # Interpolate data
        steady_data = length(size(data_les)) == 1
        if steady_data
            data_les_cont = Spline1D(z_les, data_les)
        else # unsteady data
            data_les_cont = Spline2D(time_les, z_les, data_les')
        end
        # TODO: we need to store entire solution to compare. Right now
        # we repeat the last solution along the time axis
        data_scm_arr_ = [
            q[ftc_scm, i_z, domain_decomp]
            for i in 1:n_time_points, i_z in 1:length(z_scm)
        ]
        data_scm_arr = reshape(data_scm_arr_, (n_time_points, length(z_scm)))
        data_scm[ftc] = Spline2D(time_scm, z_scm, data_scm_arr)

        # Compute data scale
        data_scale = sum(abs.(data_les)) / length(data_les)
        push!(data_scales, data_scale)

        # Plot comparison
        if plot_dir ≠ nothing
            p = plot()
            if steady_data
                data_les_cont_mapped = map(z -> data_les_cont(z), z_scm)
            else
                data_les_cont_mapped = map(z -> data_les_cont(t_cmp, z), z_scm)
            end
            plot!(
                data_les_cont_mapped,
                z_scm ./ 10^3,
                xlabel = ftc,
                ylabel = "z [km]",
                label = "PyCLES",
            )
            plot!(
                map(z -> data_scm[ftc](t_cmp, z), z_scm),
                z_scm ./ 10^3,
                xlabel = ftc,
                ylabel = "z [km]",
                label = "SCM",
            )
            mkpath(plot_dir)
            ftc_name = replace(ftc_str, "." => "_")
            savefig(joinpath(plot_dir, "$ftc_name.png"))
        end

        # Compute mean squared error (mse)
        if steady_data
            mse_single_var = sum(map(z_scm) do z
                (data_les_cont(z) - data_scm[ftc](t_cmp, z))^2
            end)
        else
            mse_single_var = sum(map(z_scm) do z
                (data_les_cont(t_cmp, z) - data_scm[ftc](t_cmp, z))^2
            end)
        end
        # Normalize by data scale
        mse[ftc] = mse_single_var / data_scale^2

        push!(mse_reductions, (best_mse[ftc] - mse[ftc]) / best_mse[ftc] * 100)
        push!(computed_mse, mse[ftc])
        push!(table_best_mse, best_mse[ftc])
    end

    # Tabulate output
    header = [
        "Variable" "Variable" "Weight" "Data scale" "MSE" "MSE" "MSE"
        "SCM (EDMF)" "PyCLES" "PyCLES" "" "Computed" "Best" "Reduction (%)"
    ]
    table_data = hcat(
        scm_variables,
        pycles_variables,
        pycles_weight,
        data_scales,
        computed_mse,
        table_best_mse,
        mse_reductions,
    )

    @info @sprintf(
        "Experiment comparison: %s at time t=%s\n",
        experiment,
        t_cmp
    )
    hl_worsened_mse = Highlighter(
        (data, i, j) -> !sufficient_mse(data[i, 5], data[i, 6]) && j == 5,
        crayon"red bold",
    )
    hl_worsened_mse_reduction = Highlighter(
        (data, i, j) -> !sufficient_mse(data[i, 5], data[i, 6]) && j == 7,
        crayon"red bold",
    )
    hl_improved_mse = Highlighter(
        (data, i, j) -> sufficient_mse(data[i, 5], data[i, 6]) && j == 7,
        crayon"green bold",
    )
    pretty_table(
        table_data,
        header,
        formatters = ft_printf("%.16e", 5:6),
        header_crayon = crayon"yellow bold",
        subheader_crayon = crayon"green bold",
        highlighters = (
            hl_worsened_mse,
            hl_improved_mse,
            hl_worsened_mse_reduction,
        ),
        crop = :none,
    )

    return mse
end

sufficient_mse(computed_mse, best_mse) = computed_mse <= best_mse + sqrt(eps())

function test_mse(computed_mse, best_mse, key)
    mse_not_regressed = sufficient_mse(computed_mse[key], best_mse[key])
    @test mse_not_regressed
    mse_not_regressed || @show key
end
