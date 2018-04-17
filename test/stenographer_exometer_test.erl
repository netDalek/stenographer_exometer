-module(stenographer_exometer_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("exometer_core/include/exometer.hrl").

-import(stenographer_exometer, [evaluate_subscription_options/2]).

evaluate_subscription_options_test() ->
    ?assertEqual({[a, b, c], #{}},
                 evaluate_subscription_options([a, b, c], [])),

    ?assertEqual({[a, b, c], #{tag => d}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, d}]}])),

    ?assertEqual({[b, c], #{tag => a}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 1}}]}])),

    ?assertEqual({[c], #{tag1 => a, tag2 => b}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag1, {from_name, 1}}, {tag2, {from_name, 2}}]}])),

    ?assertEqual({[a, c], #{tag1 => b, tag2 => d}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag1, {from_name, 2}}, {tag2, d}]}])),

    ?assertEqual({test_name, #{}},
                 evaluate_subscription_options([a, b, c], [{series_name, test_name}])),

    ?assertEqual({<<"test_name">>, #{}},
                 evaluate_subscription_options([a, b, c], [{series_name, <<"test_name">>}])),

    % ?assertEqual({test_name, #{}},
    %              evaluate_subscription_options([a, b, c], [], [], test_name, [])),

    ?assertEqual({[a, b, c], #{}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, undefined}, {undefined, value}]},
                                                           {formatting, [{purge, [{tag_keys, undefined},
                                                                                  {tag_values, undefined}]}]}
                                                          ])),

    % DefaultFormatting1 = [{purge, [{tag_keys, undefined}, {tag_values, undefined}]}],
    % ?assertEqual({[a, b, c], #{}},
    %              evaluate_subscription_options([a, b, c], [{tags, [{tag, undefined}, {undefined, value}]}], [], undefined, DefaultFormatting1)),

    ?assertEqual({[a, b, c], #{tag => b}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 2}}]},
                                                           {formatting, [{purge, [{all_from_name, false}]}]}
                                                          ])),

    % DefaultFormatting2 = [{purge, [{all_from_name, false}]}],
    % ?assertEqual({[a, b, c], #{tag => b}},
    %              evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 2}}]}], [], undefined, DefaultFormatting2)),

    ok.
