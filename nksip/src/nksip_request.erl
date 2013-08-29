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

%% @doc User Request management functions.

-module(nksip_request).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([field/2, fields/2, header/2, body/1, method/1]).
-export([is_local_route/1, provisional_reply/2]).
-export_type([id/0, field/0]).

-include("nksip.hrl").



%% ===================================================================
%% Types
%% ===================================================================

-type id() :: {req, nksip:sipapp_id(), nksip:call_id(), integer()}.

-type field() :: local | remote | method | ruri | parsed_ruri | aor | call_id | vias | 
                  parsed_vias | from | parsed_from | to | parsed_to | cseq | parsed_cseq |
                  cseq_num | cseq_method | forwards | routes | parsed_routes | 
                  contacts | parsed_contacts | content_type | parsed_content_type | 
                  headers | body | dialog_id | sipapp_id.



%% ===================================================================
%% Public
%% ===================================================================

%% @doc Gets specific information from the `Request'. 
%% The available fields are:
%%  
%% <table border="1">
%%      <tr><th>Field</th><th>Type</th><th>Description</th></tr>
%%      <tr>
%%          <td>`sipapp_id'</td>
%%          <td>{@link nksip:sipapp_id()}</td>
%%          <td>SipApp's Id</td>
%%      </tr>
%%      <tr>
%%          <td>`method'</td>
%%          <td>{@link nksip:method()}</td>
%%          <td>Method</td>
%%      </tr>
%%      <tr>
%%          <td>`ruri'</td>
%%          <td>`binary()'</td>
%%          <td>Request-Uri</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_ruri'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>Request-Uri</td>
%%      </tr>
%%      <tr>
%%          <td>`aor'</td>
%%          <td>{@link nksip:aor()}</td>
%%          <td>Address-Of-Record of the Request-Uri</td>
%%      </tr>
%%      <tr>
%%          <td>`call_id'</td>
%%          <td>{@link nksip:call_id()}</td>
%%          <td>Call-ID Header</td>
%%      </tr>
%%      <tr>
%%          <td>`vias'</td>
%%          <td>`[binary()]'</td>
%%          <td>Via Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_vias'</td>
%%          <td>`['{@link nksip:via()}`]'</td>
%%          <td>Via Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`from'</td>
%%          <td>`binary()'</td>
%%          <td>From Header</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_from'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>From Header</td>
%%      </tr>
%%      <tr>
%%          <td>`to'</td>
%%          <td>`binary()'</td>
%%          <td>To Header</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_to'</td>
%%          <td>{@link nksip:uri()}</td>
%%          <td>To Header</td>
%%      </tr>
%%      <tr>
%%          <td>`cseq'</td>
%%          <td>`binary()'</td>
%%          <td>CSeq Header</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_cseq'</td>
%%          <td>`{integer(), '{@link nksip:method()}`}'</td>
%%          <td>CSeq Header</td>
%%      </tr>
%%      <tr>
%%          <td>`forwards'</td>
%%          <td>`integer()'</td>
%%          <td>Forwards</td>
%%      </tr>
%%      <tr>
%%          <td>`routes'</td>
%%          <td>`[binary()]'</td>
%%          <td>Route Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_routes'</td>
%%          <td>`['{@link nksip:uri()}`]'</td>
%%          <td>Route Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`contacts'</td>
%%          <td>`[binary()]'</td>
%%          <td>Contact Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_contacts'</td>
%%          <td>`['{@link nksip:uri()}`]'</td>
%%          <td>Contact Headers</td>
%%      </tr>
%%      <tr>
%%          <td>`content_type'</td>
%%          <td>`binary()'</td>
%%          <td>Content-Type Header</td>
%%      </tr>
%%      <tr>
%%          <td>`parsed_content_type'</td>
%%          <td>`['{@link nksip_lib:token()}`]'</td>
%%          <td>Content-Type Header</td>
%%      </tr>
%%      <tr>
%%          <td>`headers'</td>
%%          <td>`[{binary(), binary()}]'</td>
%%          <td>User headers (not listed above)</td>
%%      </tr>
%%      <tr>
%%          <td>`body'</td>
%%          <td>{@link nksip:body()}</td>
%%          <td>Parsed Body</td>
%%      </tr>
%%      <tr>
%%          <td>`dialog_id'</td>
%%          <td>{@link nksip_dialog:id()}</td>
%%          <td>Dialog's Id (if the request has To Tag)</td>
%%      </tr>
%%      <tr>
%%          <td>`local'</td>
%%          <td>`{'{@link nksip:protocol()}, {@link inet:ip_address()}, 
%%                  {@link inet:port_number()}`}'</td>
%%          <td>Local transport protocol, ip and port of a request</td>
%%      </tr>
%%      <tr>
%%          <td>`remote'</td>
%%          <td>`{'{@link nksip:protocol()}, {@link inet:ip_address()}, 
%%                  {@link inet:port_number()}`}'</td>
%%          <td>Remote transport protocol, ip and port of a request</td>
%%      </tr>
%% </table>

field(#sipmsg{class1=req}=Req, Field) -> 
    nksip_sipmsg:field(Req, Field);

field({req, _, _, _}=ReqId, Field) -> 
    nksip_sipmsg:field(ReqId, Field).


fields(#sipmsg{class1=req}=Req, Fields) -> 
    nksip_sipmsg:fields(Req, Fields);

fields({req, _, _, _}=ReqId, Fields) -> 
    nksip_sipmsg:fields(ReqId, Fields).


header(#sipmsg{class1=req}=Req, Name) -> 
    nksip_sipmsg:header(Req, Name);

header({req, _, _, _}=ReqId, Name) -> 
    nksip_sipmsg:header(ReqId, Name).



%% @doc Gets the <i>method</i> of a `Request'.
-spec method(id()|nksip:request()) -> nksip:method().

method(Req) -> 
    field(Req, method).


%% @doc Gets the <i>body</i> of a `Request'.
-spec body(id()|nksip:request()) -> nksip:body().

body(Req) -> 
    field(Req, body).



%% @doc Sends a <i>provisional response</i> to a request.
-spec provisional_reply(id(), nksip:sipreply()) -> 
    ok | {error, Error}
    when Error :: unknown_request | invalid_response | network_error | invalid_request.

provisional_reply(Req, SipReply) ->
    case nksip_reply:reqreply(SipReply) of
        #reqreply{code=Code} = Resp when Code > 100, Code < 200 ->
            nksip_call_router:sync_reply(Req, Resp);
        _ ->
            {error, invalid_response}
    end.


%% @doc Checks if this request would be sent to a local address in case of beeing proxied.
%% It will return `true' if the first <i>Route</i> header points to a local address
%% or the <i>Request-Uri</i> if there is no <i>Route</i> headers.
-spec is_local_route(id()|nksip:request()) -> boolean().

is_local_route(Req) ->
    case fields(Req, [sipapp_id, parsed_ruri, parsed_routes]) of
        {ok, [AppId, RUri, []]} -> nksip_transport:is_local(AppId, RUri);
        {ok, [AppId, _, [Route|_]]} -> nksip_transport:is_local(AppId, Route);
        {error, Error} -> {error, Error}
    end.




%% ===================================================================
%% Internal
%% ===================================================================





