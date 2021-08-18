using Agents
using Random

CONTRIBUTION_SHORTAGE = :contribution_shortage

@enum ContributionMode no_contribution fixed_contribution on_demand_contribution

function set_sumsy_active!(actor::Actor, model, flag::Bool)
    set_sumsy_active!(actor.balance, model.sumsy, flag)
    set_sumsy_active!(actor.balance, model.contribution_settings, flag)
end

is_sumsy_active(actor::Actor, model) = is_sumsy_active(actor.balance, model.sumsy)
process_sumsy!(actor::Actor, sumsy::SuMSy, step::Int) = process_sumsy!(actor.balance, sumsy, step)
calculate_demurrage(actor::Actor, sumsy::SuMSy, step::Int) = calculate_demurrage(actor.balance, sumsy, step)
sumsy_balance(actor::Actor, model) = sumsy_balance(actor.balance, model.sumsy)
sumsy_balance(balance::Balance, model) = sumsy_balance(balance, model.sumsy)
collected_contributions(model) = sumsy_balance(model.contribution_balance, model)

function create_sumsy_model(sumsy::SuMSy,
                            contribution_mode::ContributionMode = no_contribution;
                            contribution_free::Real = sumsy.dem_free,
                            contribution_tiers::DemSettings = 0,
                            contribution_balance::Balance = Balance(),
                            interval::Int = sumsy.interval)
    model = create_econo_model()
    sumsy.id = :sumsy
    sumsy.dem_free_entry = SUMSY_DEM_FREE(sumsy.id)
    model.properties[:sumsy] = sumsy
    model.properties[:contribution_mode] = contribution_mode

    if contribution_mode != no_contribution
        contribution_settings = SuMSy(:contribution, 0, contribution_free, contribution_tiers, interval, demurrage_comment = "Contribution")
        model.properties[:contribution_settings] = contribution_settings
        model.properties[:contribution_balance] = contribution_balance

        if contribution_mode == on_demand_contribution
            model.properties[:requested_contribution] = Currency(0)
            model.properties[CONTRIBUTION_SHORTAGE] = Currency(0)
        end
    end

    return model
end

function sumsy_model_step!(model)
    econo_model_step!(model)

    if model.contribution_mode == fixed_contribution
        for actor in allagents(model)
            _, contribution = process_sumsy!(actor, model.contribution_settings, model.step)
            book_asset!(model.contribution_balance, SUMSY_DEP, contribution, model.step, comment = model.contribution_settings.demurrage_comment)
        end
    elseif model.contribution_mode == on_demand_contribution
        collect_contribution!(model)
    end

    for actor in allagents(model)
        process_sumsy!(actor, model.sumsy, model.step)
    end
end

function sumsy_step!(model, steps::Integer = 1)
    step!(model, actor_step!, sumsy_model_step!, steps, false)
end

request_contribution!(model, amount::Real) = (model.requested_contribution += amount)

function collect_contribution!(model)
    if mod(model.step, model.contribution_settings.interval) == 0 &&
        model.contribution_mode != no_contribution
        # Tuple is: [real contribution, max contribution], actor. This way sorting on highest contribution is posible.
        contributions = Vector{Tuple{Vector{Currency}, Actor}}(undef, nagents(model))
        max_total_contribution = Currency(0)
        total_contribution = Currency(0)
        i = 1

        for actor in allagents(model)
            if is_sumsy_active(actor, model)
                max_contribution = calculate_demurrage(actor, model.contribution_settings, model.step)
                contributions[i] = ([0, max_contribution], actor)
                max_total_contribution += max_contribution
            else
                contributions[i] = ([0, 0], actor)
            end

            i += 1
        end

        if model.contribution_mode == fixed_contribution
            requested_contribution = max_total_contribution
        else
            requested_contribution = model.requested_contribution
            model.requested_contribution = Currency(0)
        end

        if max_total_contribution > 0
            if model.contribution_mode == fixed_contribution
                fraction = 1
            else
                fraction = Percentage(requested_contribution / max_total_contribution)
            end

            for contribution in contributions
                contribution[1][1] = contribution[1][2] * fraction
                total_contribution += contribution[1][1]
            end

            # No more than the maximum contribution can be gathered
            requested_total_contribution = min(max_total_contribution, requested_contribution)
            sort!(contributions, rev = true)
            i = 1

            # make sure the requested amount is collected. Extra contributions are gathered from the accounts with highest balance first.
            while total_contribution < requested_total_contribution
                contributions[i][1][1] += 0.01
                total_contribution += 0.01
                i < nagents(model) ? i += 1 : i = 0
            end

            for contribution in contributions
                sumsy_transfer!(contribution[2].balance, model.contribution_balance, model.sumsy, contribution[1][1], model.step, comment = model.contribution_settings.demurrage_comment)
            end
        end

        if model.contribution_mode == on_demand_contribution
            # Store contribution shortage, if any.
            model.contribution_shortage = requested_contribution - total_contribution
        end
    end
end
