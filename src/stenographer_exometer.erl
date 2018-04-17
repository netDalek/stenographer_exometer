-module(stenographer_exometer).

-behaviour(exometer_report).

%% gen_server callbacks
-export([exometer_init/1,
         exometer_info/2,
         exometer_cast/2,
         exometer_call/3,
         exometer_report/5,
         exometer_subscribe/5,
         exometer_unsubscribe/4,
         exometer_newentry/2,
         exometer_setopts/4,
         exometer_terminate/2]).

-include_lib("exometer_core/include/exometer.hrl").

-type options() :: [{atom(), any()}].
-type value() :: any().
-type callback_result() :: {ok, state()} | any().

-record(state, {
          metrics :: map()
         }).
-type state() :: #state{}.


%% ===================================================================
%% Public API
%% ===================================================================
-spec exometer_init(options()) -> callback_result().
exometer_init(_Opts) ->
    error_logger:info_msg("[~s] starting", [?MODULE]),
    State =  #state{
                metrics = maps:new()
               },
    {ok, State}.

-spec exometer_report(exometer_report:metric(),
                      exometer_report:datapoint(),
                      exometer_report:extra(),
                      value(),
                      state()) -> callback_result().
exometer_report(Metric, DataPoint, _Extra, Value, #state{metrics = Metrics}) ->
    % error_logger:info_msg("exometer_report ~p", [[Metric, DataPoint, _Extra, Value]]),
    case maps:get(Metric, Metrics, not_found) of
        {MetricName, Tags} ->
            stenographer:send(name(MetricName), [{DataPoint, Value}], Tags);
        Error ->
            error_logger:warning_msg("InfluxDB reporter got trouble when looking ~p metric's tag: ~p",
                     [Metric, Error]),
            Error
    end.

-spec exometer_subscribe(exometer_report:metric(),
                         exometer_report:datapoint(),
                         exometer_report:interval(),
                         exometer_report:extra(),
                         state()) -> callback_result().
exometer_subscribe(Metric, _DataPoint, _Interval, SubscribeOpts, #state{metrics=Metrics} = State) ->
    {MetricName, Tags} = evaluate_subscription_options(Metric, SubscribeOpts),
    case MetricName of
        [] ->
            exit({invalid_metric_name, MetricName});
        _  ->
            NewMetrics = maps:put(Metric, {MetricName, Tags}, Metrics),
            {ok, State#state{metrics = NewMetrics}}
    end.

-spec exometer_unsubscribe(exometer_report:metric(),
                           exometer_report:datapoint(),
                           exometer_report:extra(),
                           state()) -> callback_result().
exometer_unsubscribe(Metric, _DataPoint, _Extra,
                     #state{metrics = Metrics} = State) ->
    {ok, State#state{metrics = maps:remove(Metric, Metrics)}}.

-spec exometer_call(any(), pid(), state()) ->
    {reply, any(), state()} | {noreply, state()} | any().
exometer_call(_Unknown, _From, State) ->
    {ok, State}.

-spec exometer_cast(any(), state()) -> {noreply, state()} | any().
exometer_cast(_Unknown, State) ->
    {ok, State}.

-spec exometer_info(any(), state()) -> callback_result().
exometer_info(_Unknown, State) ->
    {ok, State}.

-spec exometer_newentry(exometer:entry(), state()) -> callback_result().
exometer_newentry(_Entry, State) ->
    {ok, State}.

-spec exometer_setopts(exometer:entry(), options(),
                       exometer:status(), state()) -> callback_result().
exometer_setopts(_Metric, _Options, _Status, State) ->
    {ok, State}.

-spec exometer_terminate(any(), state()) -> any().
exometer_terminate(Reason, _) ->
    error_logger:info_msg("InfluxDB reporter is terminating with reason: ~p~n", [Reason]),
    ignore.


%% ===================================================================
%% Internal functions
%% ===================================================================

-spec del_indices(list(), [integer()]) -> list().
del_indices(List, Indices) ->
    SortedIndices = lists:reverse(lists:usort(Indices)),
    case length(SortedIndices) == length(Indices) of
        true -> del_indices1(List, SortedIndices);
        false -> exit({invalid_indices, Indices})
    end.

-spec del_indices1(list(), [integer()]) -> list().
del_indices1(List, []) -> List;
del_indices1([], Indices = [ _Index | _Indices1 ]) -> exit({too_many_indices, Indices});
del_indices1(List, [Index | Indices]) when length(List) >= Index, Index > 0 ->
    {L1, [_|L2]} = lists:split(Index-1, List),
    del_indices1(L1 ++ L2, Indices);
del_indices1(_List, Indices) ->
    exit({invalid_indices, Indices}).

-spec evaluate_subscription_options(list(), [{atom(), value()}]) -> {list() | atom(), map()}.
evaluate_subscription_options(MetricId, undefined) ->
  evaluate_subscription_options(MetricId, []);
evaluate_subscription_options(MetricId, Options) ->
    TagOpts = proplists:get_value(tags, Options, []),
    TagsResult = evaluate_subscription_tags(MetricId, TagOpts),
    FormattingOpts = proplists:get_value(formatting, Options, []),
    FormattingResult = evaluate_subscription_formatting(TagsResult, FormattingOpts),
    SeriesName = proplists:get_value(series_name, Options, undefined),
    {FinalMetricId, NewTags} = evaluate_subscription_series_name(FormattingResult, SeriesName),
    TagMap = maps:from_list(NewTags),
    {FinalMetricId, TagMap}.

-spec evaluate_subscription_tags(list(), [{atom(), value()}]) -> 
    {list(), [{atom(), value()}], [integer()]}.
evaluate_subscription_tags(MetricId, TagOpts) ->
    evaluate_subscription_tags(MetricId, TagOpts, [], []).

-spec evaluate_subscription_tags(list(), [{atom(), value()}], [{atom(), value()}], [integer()]) -> 
    {list(), [{atom(), value()}], [integer()]}.
evaluate_subscription_tags(MetricId, [], TagAcc, PosAcc) ->
    {MetricId, TagAcc, PosAcc};
evaluate_subscription_tags(MetricId, [{TagKey, {from_name, Pos}} | TagOpts], TagAcc, PosAcc)
    when is_number(Pos), length(MetricId) >= Pos, Pos > 0 ->
    NewTagAcc = TagAcc ++ [{TagKey, lists:nth(Pos, MetricId)}],
    NewPosAcc = PosAcc ++ [Pos],
    evaluate_subscription_tags(MetricId, TagOpts, NewTagAcc, NewPosAcc);
evaluate_subscription_tags(MetricId, [TagOpt = {TagKey, {from_name, Name}} | TagOpts], TagAcc, PosAcc) ->
    case string:str(MetricId, [Name]) of
        0     -> exit({invalid_tag_option, TagOpt});
        Index ->
            NewTagAcc = TagAcc ++ [{TagKey, Name}],
            NewPosAcc = PosAcc ++ [Index],
            evaluate_subscription_tags(MetricId, TagOpts, NewTagAcc, NewPosAcc)
    end;
evaluate_subscription_tags(MetricId, [Tag = {_Key, _Value} | Tags], TagAcc, PosAcc) ->
    evaluate_subscription_tags(MetricId, Tags, TagAcc ++ [Tag], PosAcc);
evaluate_subscription_tags(_MetricId, [Tag | _] , _TagAcc, _PosAcc) ->
    exit({invalid_tag_option, Tag}).

-spec evaluate_subscription_formatting({list(), [{atom(), value()}], [integer()]}, term())
                                       -> {list(), [{atom(), value()}]}.
evaluate_subscription_formatting({MetricId, Tags, FromNameIndices}, FormattingOpts) ->
    ToPurge = proplists:get_value(purge, FormattingOpts, []),
    KeysToPurge = proplists:get_all_values(tag_keys, ToPurge),
    ValuesToPurge = proplists:get_all_values(tag_values, ToPurge),
    PurgedTags = [{TagKey, TagValue} || {TagKey, TagValue} <- Tags,
                                        lists:member(TagKey, KeysToPurge) == false,
                                        lists:member(TagValue, ValuesToPurge) == false],
    FromNamePurge = proplists:get_value(all_from_name, ToPurge, true),
    PurgedMetricId = case FromNamePurge of
                          true  -> del_indices(MetricId, FromNameIndices);
                          false -> MetricId
                     end,
    {PurgedMetricId, PurgedTags}.

-spec evaluate_subscription_series_name({list(), [{atom(), value()}]}, atom())
                                        -> {list() | atom(), [{atom(), value()}]}.
evaluate_subscription_series_name({MetricId, Tags}, undefined) -> {MetricId, Tags};
evaluate_subscription_series_name({_MetricId, Tags}, SeriesName) -> {SeriesName, Tags}.

-spec metric_to_string(list()) -> string().
metric_to_string([Final]) -> metric_elem_to_list(Final);
metric_to_string([H | T]) ->
    metric_elem_to_list(H) ++ "_" ++ metric_to_string(T).

-spec metric_elem_to_list(atom() | string() | integer()) -> string().
metric_elem_to_list(E) when is_atom(E) -> atom_to_list(E);
metric_elem_to_list(E) when is_binary(E) -> binary_to_list(E);
metric_elem_to_list(E) when is_list(E) -> E;
metric_elem_to_list(E) when is_integer(E) -> integer_to_list(E).

-spec name(exometer_report:metric() | atom() | binary()) -> binary().
name(Metric) when is_atom(Metric) -> atom_to_binary(Metric, utf8);
name(Metric) when is_binary(Metric) -> Metric;
name(Metric) -> iolist_to_binary(metric_to_string(Metric)).
