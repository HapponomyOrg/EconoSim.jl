using Agents

@enum ContributionMode no_contribution fixed_contribution on_demand_contribution

function set_sumsy_active!(actor::Actor, model, flag::Bool)
    set_sumsy_active!(actor.balance, model.sumsy, flag)
    set_sumsy_active!(actor.balance, model.contribution_settings, flag)
end

is_sumsy_active(actor::Actor, model) = is_sumsy_active(actor.balance, model.sumsy)
process_sumsy(actor::Actor, sumsy::SuMSy, step::Int) = process_sumsy!(actor.balance, sumsy, step, booking_function = book_nothing)
calculate_demurrage(actor::Actor, sumsy::SuMSy, step::Int) = calculate_demurrage(actor.balance, sumsy, step)
sumsy_balance(actor::Actor, model) = sumsy_balance(actor.balance, model.sumsy)
sumsy_balance(balance::Balance, model) = sumsy_balance(balance, model.sumsy)
collected_contributions(model) = sumsy_balance(model.contribution_balance, model)

function create_sumsy_model(sumsy::SuMSy,
                            model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing;
                            contribution_mode::ContributionMode = no_contribution,
                            contribution_free::Real = sumsy.dem_free,
                            contribution_tiers::DemSettings = 0,
                            contribution_balance::Balance = Balance(),
                            interval::Int = sumsy.interval,
                            booking_function::Function = book_net_result!,
                            sumsy_processing = process_all_sumsy!)
    model = create_econo_model(append!(behavior_vector(sumsy_processing), behavior_vector(model_behaviors)))
    model.properties[:sumsy] = sumsy
    model.properties[:contribution_mode] = contribution_mode
    model.properties[:book_sumsy] = booking_function

    if contribution_mode != no_contribution
        contribution_settings = SuMSy(:contribution, 0, contribution_free, contribution_tiers, interval, demurrage_comment = "Contribution")
        model.properties[:contribution_settings] = contribution_settings
        model.properties[:contribution_balance] = contribution_balance

        if contribution_mode == on_demand_contribution
            model.properties[:requested_contribution] = Currency(0)
            model.properties[:contribution_shortage] = Currency(0)
        end
    end

    return model
end

function process_all_sumsy!(model)
    if model.contribution_mode != on_demand_contribution
        for actor in allagents(model)
            seed, income, demurrage = process_sumsy(actor, model.sumsy, model.step)
            contribution = CUR_0

            if model.contribution_mode == fixed_contribution
                _, _, contribution = process_sumsy(actor, model.contribution_settings, model.step)
            end

            book_sumsy!(model, actor, seed, income, demurrage, contribution)
        end
    else
        process_sumsy_collect_contribution!(model)
    end
end

request_contribution!(model, amount::Real) = (model.requested_contribution += amount)

function process_sumsy_collect_contribution!(model)
    if mod(model.step, model.contribution_settings.interval) == 0
        # Tuple is: [seed, income, demurrage, real contribution, max contribution], actor. This way sorting on highest contribution is possible.
        contributions = Vector{Tuple{Vector{Currency}, Actor}}(undef, nagents(model))
        max_total_contribution = Currency(0)
        total_contribution = Currency(0)
        i = 1

        for actor in allagents(model)
            if is_sumsy_active(actor, model)
                seed, income, demurrage = process_sumsy(actor, model.sumsy, model.step)
                max_contribution = calculate_demurrage(actor, model.contribution_settings, model.step)
                contributions[i] = ([seed, income, demurrage, 0, max_contribution], actor)
                max_total_contribution += max_contribution
            else
                contributions[i] = ([0, 0, 0, 0, 0], actor)
            end

            i += 1
        end
        
        requested_contribution = model.requested_contribution
        model.requested_contribution = CUR_0

        if max_total_contribution > 0
            # Make sure no more than the maximum contribution can be gathererd
            fraction = min(Percentage(requested_contribution / max_total_contribution), 1)

            for contribution in contributions
                contribution[1][4] = contribution[1][5] * fraction
                total_contribution += contribution[1][4]
            end

            # No more than the maximum contribution can be gathered
            requested_total_contribution = min(max_total_contribution, requested_contribution)
            sort!(contributions, rev = true)
            i = 1

            # Make sure the requested amount, up to the maximum contribution, is collected.
            # Extra contributions, to compensate for rounding errors, are gathered from the accounts with highest balance first.
            while total_contribution < requested_total_contribution
                contributions[i][1][4] += 0.01
                total_contribution += 0.01
                i < nagents(model) ? i += 1 : i = 0
            end

            for contribution in contributions
                book_sumsy!(model, contribution[2], contribution[1][1], contribution[1][2], contribution[1][3], contribution[1][4])
            end
        else
            # No contributions but standard SuMSy still needs to be processed.
            for contribution in contributions
                model.book_sumsy(contribution[2].balance, model.sumsy, contribution[1][1], contribution[1][2], contribution[1][3], model.step)
            end
        end

        # Store contribution shortage, if any.
        model.contribution_shortage = requested_contribution - total_contribution
    end
end

function book_sumsy!(model, actor::Actor, seed::Currency, income::Currency, demurrage::Currency, contribution::Currency)
    model.book_sumsy(actor.balance, model.sumsy, seed, income, demurrage, model.step)

    if model.contribution_mode != no_contribution
        sumsy_transfer!(actor.balance,
                        model.contribution_balance,
                        model.sumsy, contribution,
                        model.step,
                        comment = model.contribution_settings.demurrage_comment)
    end
end