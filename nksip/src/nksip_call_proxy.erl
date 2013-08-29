%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc UAS FSM proxy management functions

-module(nksip_call_proxy).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([start/4, response_stateless/2]).
-export([normalize_uriset/1]).

-include("nksip.hrl").
-include("nksip_call.hrl").

-type opt() :: stateless | record_route | follow_redirects |
                {headers, [nksip:header()]} | 
                {route, nksip:user_uri() | [nksip:user_uri()]} |
                remove_routes | remove_headers.


%% ===================================================================
%% Public
%% ===================================================================

%% @doc Routes a `Request' to set of uris, serially and/or in parallel.
%% See {@link nksip_sipapp:route/6} for an options description.
-spec start(#trans{}, nksip:request(), nksip:uri_set(), [opt()]) -> 
    ignore | nksip:sipreply() .

start(UAS, UriSet, Opts, SD) ->
    #trans{id=Id, method=Method, status=Status} = UAS,
    case normalize_uriset(UriSet) of
        [[]] when Method =:= 'ACK' -> 
            ?call_notice("UAS ~p ~p (~p) proxy has no URI to route", 
                        [Id, Method, Status], SD),
            temporarily_unavailable;
        [[]] -> 
            temporarily_unavailable;
        % [[Uri|_]|_] when Method =:= 'CANCEL' -> 
        %     cancel(UAS, Uri, Opts, SD);
        [[Uri|_]|_] when Method =:= 'ACK' -> 
            case check_forwards(UAS) of
                ok -> route_stateless(UAS, Uri, Opts, SD);
                {reply, Reply} -> Reply
            end;
        [[_|_]|_] = NUriSet -> 
            route(UAS, NUriSet, Opts, SD)
    end.



route(UAS, [[First|_]|_]=UriSet, Opts, SD) ->
    #trans{method=Method, request=#sipmsg{opts=ReqOpts}=Req} = UAS,
    Req1 = case lists:member(record_route, Opts) of 
        true when Method=:='INVITE' -> 
            Req#sipmsg{opts=[record_route|ReqOpts]};
        _ -> 
            % TODO 16.6.4: If ruri or top route has sips, and not received with 
            % tls, must record_route. If received with tls, and no sips in ruri
            % or top route, must record_route also
            Req
    end,
    Stateless = lists:member(stateless, Opts),
    case check_forwards(Req) of
        ok -> 
            case nksip_sipmsg:header(Req, <<"Proxy-Require">>, tokens) of
                {ok, []} when not Stateless ->
                    route_stateful(UAS#trans{request=Req1}, UriSet, Opts, SD);
                {ok, []} when Stateless ->
                    route_stateless(UAS#trans{request=Req1}, First, Opts, SD);
                {ok, PR} ->
                    Text = nksip_lib:bjoin([T || {T, _} <- PR]),
                    {bad_extension, Text}
            end;
        {reply, Reply} ->
            Reply
    end.




%% @private
-spec route_stateful(nksip:request(), nksip:uri_set(), nksip_lib:proplist(), #call{}) ->
    ignore.

route_stateful(#trans{request=Req}=UAS, UriSet, Opts, SD) ->
    Req1 = preprocess(Req, Opts),
    SD1 = nksip_call_fork:start(UAS#trans{request=Req1}, UriSet, Opts, SD),
    {stateful, SD1}.


%% @private
-spec route_stateless(nksip:request(), nksip:uri(), nksip_lib:proplist(), #call{}) -> 
    ignore.

route_stateless(#trans{request=Req}, Uri, Opts, SD) ->
    #sipmsg{method=Method, opts=ReqOpts} = Req,
    Req1 = preprocess(Req#sipmsg{ruri=Uri, opts=[stateless|ReqOpts]}, Opts),
    case nksip_request:is_local_route(Req1) of
        true -> 
            ?call_notice("Stateless proxy tried to stateless proxy a request to itself", 
                         [], SD),
            loop_detected;
        false ->
            Req2 = nksip_transport_uac:add_via(Req1),
            case nksip_transport_uac:send_request(Req2) of
                {ok, _} ->  
                    ?call_debug("Stateless proxy routing ~p to ~s", 
                                [Method, nksip_unparse:uri(Uri)], SD);
                error -> 
                    ?call_notice("Stateless proxy could not route ~p to ~s",
                                 [Method, nksip_unparse:uri(Uri)], SD)
                end,
            {stateless, SD}
    end.
    

%% @private Called from nksip_transport_uac when a request 
%% is received by a stateless proxy
-spec response_stateless(nksip:response(), #call{}) -> 
    ok.

response_stateless(#sipmsg{vias=[_|RestVia]}=Resp, SD) when RestVia=/=[] ->
    case nksip_transport_uas:send_response(Resp#sipmsg{vias=RestVia}) of
        {ok, _} -> ?call_debug("Stateless proxy sent response", [], SD);
        error -> ?call_notice("Stateless proxy could not send response", [], SD)
    end;

response_stateless(_, SD) ->
    ?call_notice("Stateless proxy could not send response: no Via", [], SD).



%%====================================================================
%% Internal 
%%====================================================================


%% @private
-spec check_forwards(nksip:request()) ->
    ok | {reply, nksip:sipreply()}.

check_forwards(#trans{method=Method, request=#sipmsg{forwards=Forwards}}) ->
    if
        is_integer(Forwards), Forwards > 0 ->   
            ok;
        Forwards=:=0, Method=:='OPTIONS' ->
            {reply, {ok, [], <<>>, [make_supported, make_accept, make_allow, 
                                        {reason, <<"Max Forwards">>}]}};
        Forwards=:=0 ->
            {reply, too_many_hops};
        true -> 
            {reply, invalid_request}
    end.


%% @private
-spec preprocess(nksip:request(), nksip_lib:proplist()) ->
    nksip:request().

preprocess(#sipmsg{forwards=Forwards, routes=Routes, headers=Headers}=Req, Opts) ->
    Routes1 = case lists:member(remove_routes, Opts) of
        true -> [];
        false -> Routes
    end,
    Headers1 = case lists:member(remove_headers, Opts) of
        true -> [];
        false -> Headers
    end,
    Req#sipmsg{
        forwards = Forwards - 1, 
        headers = nksip_lib:get_value(headers, Opts, []) ++ Headers1, 
        routes = nksip_parse:uris(nksip_lib:get_value(route, Opts, [])) ++ Routes1
    }.


%% @private Process a UriSet generating a standard [[nksip:uri()]]
%% See test bellow for examples
-spec normalize_uriset(nksip:uri_set()) ->
    [[nksip:uri()]].

normalize_uriset(#uri{}=Uri) ->
    [[Uri]];

normalize_uriset(UriSet) when is_binary(UriSet) ->
    case nksip_parse:uris(UriSet) of
        [] -> [[]];
        UriList -> [UriList]
    end;

normalize_uriset(UriSet) when is_list(UriSet) ->
    case nksip_lib:is_string(UriSet) of
        true ->
            case nksip_parse:uris(UriSet) of
                [] -> [[]];
                UriList -> [UriList]
            end;
        false ->
            normalize_uriset(single, UriSet, [], [])
    end;

normalize_uriset(_) ->
    [[]].


normalize_uriset(single, [#uri{}=Uri|R], Acc1, Acc2) -> 
    normalize_uriset(single, R, Acc1++[Uri], Acc2);

normalize_uriset(multi, [#uri{}=Uri|R], Acc1, Acc2) -> 
    case Acc1 of
        [] -> normalize_uriset(multi, R, [], Acc2++[[Uri]]);
        _ -> normalize_uriset(multi, R, [], Acc2++[Acc1]++[[Uri]])
    end;

normalize_uriset(single, [Bin|R], Acc1, Acc2) when is_binary(Bin) -> 
    normalize_uriset(single, R, Acc1++nksip_parse:uris(Bin), Acc2);

normalize_uriset(multi, [Bin|R], Acc1, Acc2) when is_binary(Bin) -> 
    case Acc1 of
        [] -> normalize_uriset(multi, R, [], Acc2++[nksip_parse:uris(Bin)]);
        _ -> normalize_uriset(multi, R, [], Acc2++[Acc1]++[nksip_parse:uris(Bin)])
    end;

normalize_uriset(single, [List|R], Acc1, Acc2) when is_list(List) -> 
    case nksip_lib:is_string(List) of
        true -> normalize_uriset(single, R, Acc1++nksip_parse:uris(List), Acc2);
        false -> normalize_uriset(multi, [List|R], Acc1, Acc2)
    end;

normalize_uriset(multi, [List|R], Acc1, Acc2) when is_list(List) -> 
    case nksip_lib:is_string(List) of
        true when Acc1=:=[] ->
            normalize_uriset(multi, R, [], Acc2++[nksip_parse:uris(List)]);
        true ->
            normalize_uriset(multi, R, [], Acc2++[Acc1]++[nksip_parse:uris(List)]);
        false when Acc1=:=[] ->  
            normalize_uriset(multi, R, [], Acc2++[nksip_parse:uris(List)]);
        false ->
            normalize_uriset(multi, R, [], Acc2++[Acc1]++[nksip_parse:uris(List)])
    end;

normalize_uriset(Type, [_|R], Acc1, Acc2) ->
    normalize_uriset(Type, R, Acc1, Acc2);

normalize_uriset(_Type, [], [], []) ->
    [[]];

normalize_uriset(_Type, [], [], Acc2) ->
    Acc2;

normalize_uriset(_Type, [], Acc1, Acc2) ->
    Acc2++[Acc1].



%% ===================================================================
%% EUnit tests
%% ===================================================================


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


normalize_test() ->
    UriA = #uri{domain=(<<"a">>)},
    UriB = #uri{domain=(<<"b">>)},
    UriC = #uri{domain=(<<"c">>)},
    UriD = #uri{domain=(<<"d">>)},
    UriE = #uri{domain=(<<"e">>)},

    ?assert(normalize_uriset([]) =:= [[]]),
    ?assert(normalize_uriset(a) =:= [[]]),
    ?assert(normalize_uriset([a,b]) =:= [[]]),
    ?assert(normalize_uriset("sip:a") =:= [[UriA]]),
    ?assert(normalize_uriset(<<"sip:b">>) =:= [[UriB]]),
    ?assert(normalize_uriset("other") =:= [[]]),
    ?assert(normalize_uriset(UriC) =:= [[UriC]]),
    ?assert(normalize_uriset([UriD]) =:= [[UriD]]),
    ?assert(normalize_uriset(["sip:a", "sip:b", UriC, <<"sip:d">>, "sip:e"]) 
                                            =:= [[UriA, UriB, UriC, UriD, UriE]]),
    ?assert(normalize_uriset(["sip:a", ["sip:b", UriC], <<"sip:d">>, ["sip:e"]]) 
                                            =:= [[UriA], [UriB, UriC], [UriD], [UriE]]),
    ?assert(normalize_uriset([["sip:a", "sip:b", UriC], <<"sip:d">>, "sip:e"]) 
                                            =:= [[UriA, UriB, UriC], [UriD], [UriE]]),
    ok.

-endif.



