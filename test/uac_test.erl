%% -------------------------------------------------------------------
%%
%% uac_test: Basic Test Suite
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

-module(uac_test).

-include_lib("eunit/include/eunit.hrl").
-include("../include/nksip.hrl").

-compile([export_all]).


uac_test_() ->
    {setup, spawn, 
        fun() -> start() end,
        fun(_) -> stop() end,
        [
            {timeout, 60, fun uac/0},
            {timeout, 60, fun info/0},
            {timeout, 60, fun message/0},
            {timeout, 60, fun timeout/0}
        ]
    }.


start() ->
    tests_util:start_nksip(),
    {ok, _} = nksip:start(client1, ?MODULE, [], [
        {from, "\"NkSIP Basic SUITE Test Client\" <sip:client1@nksip>"},
        {transports, [ {udp, all, 5070},{tls, all, 5071}]}
    ]),
            
    {ok, _} = nksip:start(client2, ?MODULE, [], [
        {from, "\"NkSIP Basic SUITE Test Client\" <sip:client2@nksip>"}]),
    tests_util:log(),
    ?debugFmt("Starting ~p", [?MODULE]).


stop() ->
    ok = nksip:stop(client1),
    ok = nksip:stop(client2).


uac() ->
    SipC1 = "sip:127.0.0.1:5070",

    {error, invalid_uri} = nksip_uac:options(client2, "sip::a", []),
    {error, {invalid, <<"from">>}} = nksip_uac:options(client2, SipC1, [{from, "<>"}]),
    {error, {invalid, <<"to">>}} = nksip_uac:options(client2, SipC1, [{to, "<>"}]),
    {error, {invalid, <<"route">>}} = nksip_uac:options(client2, SipC1, [{route, "<>"}]),
    {error, {invalid, <<"contact">>}} = nksip_uac:options(client2, SipC1, [{contact, "<>"}]),
    {error, {invalid_config, cseq_num}} = nksip_uac:options(client2, SipC1, [{cseq_num, -1}]),
    lager:error("Next error about 'unknown_siapp' is expected"),
    {error, sipapp_not_found} = nksip_uac:options(none, SipC1, []),
    % lager:error("Next error about 'too_many_calls' is expected"),
    % nksip_counters:incr(nksip_calls, 1000000000),
    % {error, too_many_calls} = nksip_uac:options(client2, SipC1, []),
    % nksip_counters:incr(nksip_calls, -1000000000),

    Self = self(),
    Ref = make_ref(),
    Fun = fun(Reply) -> 
        case Reply of
            {req, Req, _Call} -> Self ! {Ref, {req, Req}};
            {resp, Code, Resp, _Call} -> Self ! {Ref, {resp, Code, Resp}};
            {error, Error} -> Self ! {Ref, {error, Error}}
        end
    end,

    CB = {callback, Fun},
    Hds = [{add, "x-nk-op", busy}, {add, "x-nk-prov", "true"}],

    lager:info("Next two infos about connection error to port 50600 are expected"),
    {error, service_unavailable} =
        nksip_uac:options(client2, "<sip:127.0.0.1:50600;transport=tcp>", []),
    
    % Async, error
    {async, _ReqId1} = nksip_uac:options(client2, "<sip:127.0.0.1:50600;transport=tcp>", 
                                        [async, CB, get_request]),
    receive 
        {Ref, {error, service_unavailable}} -> ok
        after 500 -> error(uac) 
    end,

    % Sync
    {ok, 200, Values2} = nksip_uac:options(client2, SipC1, [{meta, [app_name, id, call_id]}]),
    [{app_name, client2}, {id, RespId2}, {call_id, CallId2}] = Values2,
    CallId2 = nksip_response:call_id(RespId2),
    error = nksip_dialog:meta(status, RespId2),
    {error, unknown_dialog} = nksip_uac:options(RespId2, []),

    % Sync, callback for request
    {ok, 200, [{id, RespId3}]} = 
        nksip_uac:options(client2, SipC1, [CB, get_request, {meta, [id]}]),
    CallId3 = nksip_response:call_id(RespId3),
    receive 
        {Ref, {req, #sipmsg{class={req, _}, call_id=CallId3}}} -> ok
        after 500 -> error(uac) 
    end,

    % Sync, callback for request and provisional response
    {ok, 486, [{call_id, CallId4}, {id, RespId4}]} = 
        nksip_uac:invite(client2, SipC1, [CB, get_request, {meta, [call_id, id]}|Hds]),

    lager:notice("RESPID4: ~p", [RespId4]),


    CallId4 = nksip_response:call_id(RespId4),
    % DlgId4 = nksip_dialog:get_id(RespId4),
    receive 
        {Ref, {req, Req4}} -> 
            CallId4 = nksip_request:meta(call_id, Req4)
        after 500 -> 
            error(uac) 
    end,
    receive 
        {Ref, {resp, 180, Resp4}} ->
            [{dialog_id, DlgId4}, {call_id, CallId4}, {id, RespId4_180}] =
                nksip_response:meta([dialog_id, call_id, id], Resp4),
            CallId4 = nksip_response:call_id(RespId4_180),
            CallId4 = nksip_dialog:call_id(DlgId4)
        after 500 -> 
            error(uac) 
    end,

    % Async
    {async, ReqId6} = nksip_uac:invite(client2, SipC1, [async, CB, get_request | Hds]),
    CallId6 = nksip_request:call_id(ReqId6),
    CallId6 = nksip_request:meta(call_id, ReqId6),
    receive 
        {Ref, {req, Req6}} -> 
            ReqId6 = nksip_request:meta(id, Req6),
            CallId6 = nksip_request:meta(call_id, Req6)
        after 500 -> 
            error(uac) 
    end,
    receive 
        {Ref, {resp, 180, _}} -> ok
        after 500 -> error(uac) 
    end,
    receive 
        {Ref, {resp, 486, _}} -> ok
        after 500 -> error(uac) 
    end,
    ok.



info() ->
    SipC1 = "sip:127.0.0.1:5070",
    Hd1 = {add, <<"x-nk-op">>, <<"ok">>},
    {ok, 200, [{dialog_id, DialogId2}]} = nksip_uac:invite(client2, SipC1, [Hd1]),
    ok = nksip_uac:ack(DialogId2, []),
    Fs = {meta, [<<"x-nk-method">>, <<"x-nk-dialog">>]},
    DialogId1 = nksip_dialog:remote_id(DialogId2, client1),

    {ok, 200, Values1} = nksip_uac:info(DialogId2, [Fs]),
    [{<<"x-nk-method">>, [<<"info">>]}, {<<"x-nk-dialog">>, [DialogId1]}] = Values1,

    % Now we forcefully stop dialog at client1. At client2 is still valid, and can send the INFO
    ok = nksip_dialog:stop(DialogId1),
    {ok, 481, []} = nksip_uac:info(DialogId2, []), 

    % The dialog at client2, at receiving a 481 (even for INFO) is destroyed before the BYE
    {error, unknown_dialog} = nksip_uac:bye(DialogId2, []),
    ok.


timeout() ->
    SipC1 = "sip:127.0.0.1:5070",
    {ok, _} = nksip:update(client2, [{timer_t1, 10}, {timer_c, 1}]),

    lager:notice("Next notices about several timeouts are expected"),

    {ok, 408, [{reason_phrase, <<"Timer F Timeout">>}]} = 
        nksip_uac:options(client2, "sip:127.0.0.1:9999", [{meta,[reason_phrase]}]),

    {ok, 408, [{reason_phrase, <<"Timer B Timeout">>}]} = 
        nksip_uac:invite(client2, "sip:127.0.0.1:9999", [{meta,[reason_phrase]}]),

    % REGISTER sends a provisional response, but the timeout is the same
    Hd1 = {add, <<"x-nk-sleep">>, 2000},
    {ok, 408, [{reason_phrase, <<"Timer F Timeout">>}]} = 
        nksip_uac:options(client2, SipC1, [Hd1, {meta, [reason_phrase]}]),

    % INVITE sends 
    Hds2 = [{add, "x-nk-op", busy}, {add, "x-nk-prov", "true"}, {add, "x-nk-sleep", 20000}],
    {ok, 408, [{reason_phrase, Reason}]} = 
        nksip_uac:invite(client2, SipC1, [{meta, [reason_phrase]}|Hds2]),
    
    % TODO: Should fire timer C, sometimes it fires timer B 
    case Reason of
        <<"Timer C Timeout">> -> ok;
        <<"Timer B Timeout">> -> ok
    end,
    nksip_call:clear_all(),
    ok.


message() ->
    {Ref, Hd} = tests_util:get_ref(),
    {ok, 200, []} = nksip_uac:message(client2, "sip:user@127.0.0.1:5070", [
                                      Hd, {expires, 10}, {content_type, "text/plain"},
                                      {body, <<"Message">>}]),

    receive 
        {Ref, {ok, 10, RawDate, <<"text/plain">>, <<"Message">>}} ->
            Date = httpd_util:convert_request_date(binary_to_list(RawDate)),
            true = nksip_lib:timestamp() - nksip_lib:gmt_to_timestamp(Date) < 2
        after 1000 -> 
            error(message)
    end,
    ok.



%%%%%%%%%%%%%%%%%%%%%%%  CallBacks (servers and clients) %%%%%%%%%%%%%%%%%%%%%


sip_invite(Req, _Call) ->
    tests_util:save_ref(Req),
    Op = case nksip_request:header(<<"x-nk-op">>, Req) of
        [Op0] -> Op0;
        _ -> <<"decline">>
    end,
    Sleep = case nksip_request:header(<<"x-nk-sleep">>, Req) of
        [Sleep0] -> nksip_lib:to_integer(Sleep0);
        _ -> 0
    end,
    Prov = case nksip_request:header(<<"x-nk-prov">>, Req) of
        [<<"true">>] -> true;
        _ -> false
    end,
    ReqId = nksip_request:get_id(Req),
    DialogId = nksip_dialog:get_id(Req),
    proc_lib:spawn(
        fun() ->
            if 
                Prov -> nksip_request:reply(ringing, ReqId); 
                true -> ok 
            end,
            case Sleep of
                0 -> ok;
                _ -> timer:sleep(Sleep)
            end,
            case Op of
                <<"ok">> ->
                    nksip_request:reply({ok, []}, ReqId);
                <<"answer">> ->
                    SDP = nksip_sdp:new("client2", 
                                            [{"test", 4321, [{rtpmap, 0, "codec1"}]}]),
                    nksip_request:reply({ok, [{body, SDP}]}, ReqId);
                <<"busy">> ->
                    nksip_request:reply(busy, ReqId);
                <<"increment">> ->
                    SDP1 = nksip_dialog:meta(invite_local_sdp, DialogId),
                    SDP2 = nksip_sdp:increment(SDP1),
                    nksip_request:reply({ok, [{body, SDP2}]}, ReqId);
                _ ->
                    nksip_request:reply(decline, ReqId)
            end
        end),
    noreply.


sip_options(Req, _Call) ->
    case nksip_request:header(<<"x-nk-sleep">>, Req) of
        [Sleep0] -> 
            ReqId = nksip_request:get_id(Req),
            spawn(
                fun() ->
                    nksip_request:reply(101, ReqId), 
                    timer:sleep(nksip_lib:to_integer(Sleep0)),
                    nksip_request:reply({ok, [contact]}, ReqId)
                end),
            noreply; 
        _ -> 
            {reply, {ok, [contact]}}
    end.


sip_info(Req, _Call) ->
    DialogId = nksip_dialog:get_id(Req),
    {reply, {ok, [{add, "x-nk-method", "info"}, {add, "x-nk-dialog", DialogId}]}}.


sip_message(Req, _Call) ->
    case nksip_request:header(<<"x-nk-reply">>, Req) of
        [RepBin] ->
            {Ref, Pid} = erlang:binary_to_term(base64:decode(RepBin)),
            [
                {_, Expires},
                {_, [Date]},
                {_, [ContentType]},
                {_, Body}

            ] = nksip_request:meta([expires, <<"date">>, <<"content-type">>, body], Req),
            Pid ! {Ref, {ok, Expires, Date, ContentType, Body}},
            {reply, ok};
        _ ->
            {reply, decline}
    end.

