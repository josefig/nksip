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

%% @doc User dialog management module.
%% This module implements several utility functions related to dialogs.

-module(nksip_dialog).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([field/2, fields/2, id/1, find_callid/2, stop/1, bye_all/0, stop_all/0]).
-export([get_dialog/1, get_all/0, get_all_data/0, is_authorized/1]).
-export([remote_id/2]).

-export_type([id/0, dialog/0, stop_reason/0, spec/0, status/0, field/0]).

-include("nksip.hrl").


%% ===================================================================
%% Types
%% ===================================================================

%% SIP Dialog unique ID
-type id() :: {dlg, nksip:sipapp_id(), nksip:call_id(), integer()} | undefined.

%% SIP Dialog stop reason
-type stop_reason() :: caller_bye | callee_bye | cancelled | busy | decline |
                       service_unavailable | forced_stop | {code, nksip:response_code()} |
                       proceeding_timeout | confirmed_timeout | accepted_timeout |
                       unknown.

%% SIP Dialog State
-type dialog() :: #dialog{}.

%% All the ways to specify a dialog
-type spec() :: id() | dialog() | nksip_request:id() | nksip_response:id() |
                nksip:request() | nksip:response().

%% All dialog states
-type status() :: proceeding_uac | proceeding_uas |accepted_uac | accepted_uas |
                  confirmed | bye | stop.

-type field() :: dialog_id | sipapp_id | call_id | created | updated | answered | 
                 state | expires |  local_seq | remote_seq | 
                 local_uri | parsed_local_uri | remote_uri |  parsed_remote_uri | 
                 local_target | parsed_local_target | remote_target | 
                 parsed_remote_target | route_set | parsed_route_set |
                 local_sdp | remote_sdp | stop_reason |
                 from_tag | to_tag.



%% ===================================================================
%% Public
%% ===================================================================


%% @doc Gets specific information from the dialog indicated by `DialogSpec'. 
%% The available fields are:
%%  
%% <table border="1">
%%      <tr><th>Field</th><th>Type</th><th>Description</th></tr>
%%      <tr>
%%          <td>`sipapp_id'</td>
%%          <td>{@link nksip:sipapp_id()}</td>
%%          <td>SipApp that created the dialog</td>
%%      </tr>
%%      <tr>
%%          <td>`call_id'</td>
%%          <td>{@link nksip:call_id()}</td>
%%          <td>Call-ID</td>
%%      </tr>
%%      <tr>
%%          <td>`created'</td>
%%          <td>{@link nksip_lib:timestamp()}</td>
%%          <td>Creation timestamp</td>
%%      </tr>
%%      <tr>
%%          <td>`updated'</td>
%%          <td>{@link nksip_lib:timestamp()}</td>
%%          <td>Last update timestamp</td>
%%      </tr>
%%      <tr>
%%          <td>`answered'</td>
%%          <td>{@link nksip_lib:timestamp()}`|undefined'</td>
%%          <td>Answer (first 2xx response) timestamp</td>
%%      </tr>
%%      <tr>
%%          <td>`state'</td>
%%          <td>{@link state()}</td>
%%          <td>Current dialog state</td>
%%      </tr>
%%      <tr>
%%          <td>`expires'</td>
%%          <td>`integer()'</td>
%%          <td>Seconds to expire current state</td>
%%      </tr>
%%      <tr>
%%          <td>`local_seq'</td>
%%          <td>{@link nksip:cseq()}</td>
%%          <td>Local CSeq number</td>
%%      </tr>
%%      <tr>
%%          <td>`remote_seq'</td>
%%          <td>{@link nksip:cseq()}</td>
%%          <td>Remote CSeq number</td>
%%      </tr>
%%      <tr>
%%          <td>`local_uri'</td>
%%          <td>`binary()'</td>
%%          <td>Local URI</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_local_uri'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>Local URI</td>
%%      </tr>
%%      <tr>
%%          <td>`remote_uri'</td>
%%          <td>`binary()'</td>
%%          <td>Remote URI</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_remote_uri'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>Remote URI</td>
%%      </tr>
%%      <tr>
%%          <td>`local_target'</td>
%%          <td>`binary()'</td>
%%          <td>Local Target URI</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_local_target'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>Local Target URI</td>
%%      </tr>
%%      <tr>
%%          <td>`remote_target'</td>
%%          <td>`binary()'</td>
%%          <td>Remote Target URI</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_remote_target'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>Remote Target URI</td>
%%      </tr>
%%      <tr>
%%          <td>`early'</td>
%%          <td>`boolean()'</td>
%%          <td>Early dialog (no final response yet)</td>
%%      </tr>
%%      <tr>
%%          <td>`secure'</td>
%%          <td>`boolean()'</td>
%%          <td>Secure (sips) dialog</td>
%%      </tr>
%%      <tr>
%%          <td>`route_set'</td>
%%          <td>`[binary()]'</td>
%%          <td>Route Set</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_route_set'</td>
%%          <td>`['{@link nksip:uri()}`]'</td>
%%          <td>Route Set</td>
%%      </tr>
%%      <tr>
%%          <td>`local_sdp'</td>
%%          <td>{@link nksip:sdp()}`|undefined'</td>
%%          <td>Current local SDP</td>
%%      </tr>
%%      <tr>
%%          <td>`remote_sdp'</td>
%%          <td>{@link nksip:sdp()}`|undefined'</td>
%%          <td>Current remote SDP</td>
%%      </tr>
%%      <tr>
%%          <td>`stop_reason'</td>
%%          <td>{@link stop_reason()}</td>
%%          <td>Dialog stop reason</td>
%%      </tr>
%% </table>
-spec field(spec(), field()) -> term() | {error, Error}
    when Error :: unknown_dialog | terminated_dialog | timeout_dialog. 

field(#dialog{}=Dialog, Field) ->
    get_field(Dialog, Field);

field(DialogSpec, Field) -> 
    case fields(DialogSpec, [Field]) of
        {ok, [Value|_]} -> {ok, Value};
        {error, Error} -> {error, Error}
    end.


%% @doc Gets a number of fields from the `Request' as described in {@link field/2}
-spec fields([field()], id()) -> [term()] | {error, Error}
    when Error :: unknown_dialog | terminated_dialog | timeout_dialog. 

fields(#dialog{}=Dialog, Fields) when is_list(Fields) ->
    {ok, [get_field(Dialog, Field) || Field <- Fields]};

fields(DialogSpec, Fields) when is_list(Fields) ->
    nksip_call_router:get_dialog_fields(DialogSpec, Fields).


%% @doc Calculates a <i>Dialog's Id</i> from a {@link nksip_request:id()}, 
%% {@link nksip_response:id()}, {@link nksip:request()} or {@link nksip:response()}.
%% <i>Dialog Ids</i> are calculated as a hash over <i>Call-ID</i>, <i>From</i> tag 
%% and <i>To</i> Tag. If From Tag and To Tag are swapped the resulting Id is the same.
-spec id(spec()) ->
    id().

id(#dialog{id=DialogId, app_id=AppId, call_id=CallId}) ->
    {dlg, AppId, CallId, DialogId};

id({dlg, AppId, CallId, DialogId}) -> 
    {dlg, AppId, CallId, DialogId};

id(#sipmsg{sipapp_id=AppId, call_id=CallId, from_tag=FromTag, to_tag=ToTag})
    when FromTag =/= <<>>, ToTag =/= <<>> ->
    dialog_id(AppId, CallId, FromTag, ToTag);

id(#sipmsg{from_tag=FromTag, to_tag=(<<>>), method='INVITE', opts=Opts}=SipMsg)
    when FromTag =/= <<>> ->
    #sipmsg{sipapp_id=AppId, call_id=CallId} = SipMsg,
    case nksip_lib:get_binary(to_tag, Opts) of
        <<>> -> undefined;
        ToTag -> dialog_id(AppId, CallId, FromTag, ToTag)
    end;
        
id({Type, AppId, CallId, _}=SipMsgId) when Type=:=req; Type=:=resp ->
    case catch nksip_call_router:get_fields([from_tag, to_tag], SipMsgId) of
        {ok, [FromTag, ToTag]} -> dialog_id(AppId, CallId, FromTag, ToTag);
        _ -> undefined
    end;

id(_) ->
    undefined.


get_dialog(DialogSpec) ->
    nksip_call_router:get_dialog(DialogSpec).


get_all() ->
    nksip_call_router:get_all_dialogs().


%% @doc Finds all existing dialogs' processes having a Call-ID
-spec find_callid(nksip:sipapp_id(), nksip:call_id()) ->
    [id()].

find_callid(AppId, CallId) ->
    nksip_call_router:get_all_dialogs(AppId, CallId).

%% @doc Sends an in-dialog BYE to all existing dialogs.
-spec bye_all() ->
    ok.

bye_all() ->
    Fun = fun(DialogId) -> nksip_uac:bye(DialogId, [async]) end,
    lists:foreach(Fun, get_all()).


%% @doc Stops an existing dialog (remove it from memory).
-spec stop(spec()) ->
    ok.

stop(DialogSpec) ->
    nksip_call_router:stop_dialog(DialogSpec).


%% @doc Stops all current dialogs.
-spec stop_all() ->
    ok.

stop_all() ->
    lists:foreach(fun stop/1, get_all()).


%% @doc Checks if a request is part of an already authenticated dialog,
%% and it comes from the same ip and port.
-spec is_authorized(Request::nksip:request()) ->
    boolean().

is_authorized(Req) ->
    #sipmsg{sipapp_id=AppId, call_id=CallId, method=Method,
            transport=#transport{remote_ip=Ip, remote_port=Port}} = Req,
    case nksip_dialog:id(Req) of
        <<>> ->
            false;
        DialogId ->
            case nksip_proc:values({nksip_dialog_auth, DialogId}) of
                [{Remotes, _Pid}] -> 
                    case lists:member({Ip, Port}, Remotes) of
                        true ->
                            ?debug(AppId, CallId, 
                                   "authorized ~p dialog request from ~p", 
                                   [Method, {Ip, Port}]),
                            true;
                        false ->
                            ?debug(AppId, CallId, 
                                   "unauthorized ~p dialog request from ~p"
                                   " (authorized are ~p)", 
                                   [Method, {Ip, Port}, Remotes]),
                            false
                    end;
                _ -> 
                    false
            end
    end.



%% ===================================================================
%% Private
%% ===================================================================


%% @private
dialog_id(AppId, CallId, FromTag, ToTag) ->
    {A, B} = case FromTag < ToTag of
        true -> {FromTag, ToTag};
        false -> {ToTag, FromTag}
    end,
    {dlg, AppId, CallId, erlang:phash2({A, B})}.



%% @private Dumps all dialog information
%% Do not use it with many active dialogs!!
-spec get_all_data() ->
    [{id(), nksip_lib:proplist()}].

get_all_data() ->
    Now = nksip_lib:timestamp(),
    Fun = fun(DialogId, Acc) ->
        case get_dialog(DialogId) of
            {ok, Dialog} ->
                Data = {DialogId, [
                    {sipapp_id, Dialog#dialog.app_id},
                    {call_id, Dialog#dialog.call_id},
                    {status, Dialog#dialog.status},
                    {local_uri, nksip_unparse:uri(Dialog#dialog.local_uri)},
                    {remote_uri, nksip_unparse:uri(Dialog#dialog.remote_uri)},
                    {created, Dialog#dialog.created},
                    {elapsed, Now - Dialog#dialog.created},
                    {updated, Dialog#dialog.updated},
                    % {timeout, Dialog#dialog.expires},
                    {answered, Dialog#dialog.answered},
                    {local_seq, Dialog#dialog.local_seq},
                    {remote_seq, Dialog#dialog.remote_seq},
                    {local_target, nksip_unparse:uri(Dialog#dialog.local_target)},
                    {remote_target, nksip_unparse:uri(Dialog#dialog.remote_target)},
                    {route_set, 
                        [nksip_unparse:uri(Route) || Route <- Dialog#dialog.route_set]},
                    {early, Dialog#dialog.early},
                    % {local_sdp, nksip_sdp:unparse(Dialog#dialog.local_sdp)},
                    % {remote_sdp, nksip_sdp:unparse(Dialog#dialog.remote_sdp)}
                    {local_sdp, Dialog#dialog.local_sdp},
                    {remote_sdp, Dialog#dialog.remote_sdp}
                ]},
                [Data|Acc];
            _ ->
                Acc
        end
    end,
    lists:foldl(Fun, [], get_all()).


%% @private Only for testing
remote_id(AppId, DialogId) ->
    [CallId, FromTag, ToTag] = fields(DialogId, [call_id, from_tag, to_tag]),
    dialog_id(AppId, CallId, FromTag, ToTag).




%% ===================================================================
%% Internal
%% ===================================================================


%% @private Extracts a specific field from the request
%% See {@link nksip_request:field/2}.
-spec get_field(field(), dialog()) -> any().

get_field(D, Field) ->
    case Field of
        id -> D#dialog.id;
        sipapp_id -> D#dialog.app_id;
        call_id -> D#dialog.call_id;
        created -> D#dialog.created;
        updated -> D#dialog.updated;
        answered -> D#dialog.answered;
        status -> D#dialog.status;
        local_seq -> D#dialog.local_seq; 
        remote_seq  -> D#dialog.remote_seq; 
        local_uri -> nksip_unparse:uri(D#dialog.local_uri);
        parsed_local_uri -> D#dialog.local_uri;
        remote_uri -> nksip_unparse:uri(D#dialog.remote_uri);
        parsed_remote_uri -> D#dialog.remote_uri;
        local_target -> nksip_unparse:uri(D#dialog.local_target);
        parsed_local_target -> D#dialog.local_target;
        remote_target -> nksip_unparse:uri(D#dialog.remote_target);
        parsed_remote_target -> D#dialog.remote_target;
        route_set -> [nksip_lib:to_binary(Route) || Route <- D#dialog.route_set];
        parsed_route_set -> D#dialog.route_set;
        early -> D#dialog.early;
        secure -> D#dialog.secure;
        local_sdp -> D#dialog.local_sdp;
        remote_sdp -> D#dialog.remote_sdp;
        stop_reason -> D#dialog.stop_reason;
        from_tag -> nksip_lib:get_binary(tag, (D#dialog.local_uri)#uri.ext_opts);
        to_tag -> nksip_lib:get_binary(tag, (D#dialog.remote_uri)#uri.ext_opts);
        timeout -> round(erlang:read_timer(D#dialog.timeout_timer)/1000);
        _ -> invalid_field 
    end.






