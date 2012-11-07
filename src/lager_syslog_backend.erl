%% Copyright (c) 2011-2012 Basho Technologies, Inc.  All Rights Reserved.
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

%% @doc Syslog backend for lager.

-module(lager_syslog_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
        code_change/3]).

-record(state, {level, formatter,format_config}).

-include_lib("lager/include/lager.hrl").

-define(TERSE_FORMAT,[time, " [", severity,"] ", message]).

%% @private
init([Ident, Facility, Level]) when is_atom(Level) ->
    init([Ident, Facility, [Level, {lager_default_formatter, ?TERSE_FORMAT}]]);
init([Ident, Facility, [Level, true]]) -> % for backwards compatibility
    init([Ident, Facility, [Level, {lager_default_formatter,[{eol, "\r\n"}]}]]);
init([Ident, Facility, [Level, false]]) -> % for backwards compatibility
    init([Ident, Facility, [Level, {lager_default_formatter, ?TERSE_FORMAT}]]);
init([Ident, Facility, [Level, {Formatter, FormatterConfig}]]) when is_atom(Level), is_atom(Formatter) ->	
	case application:start(syslog) of
        ok ->
            init2([Ident, Facility, [Level, {Formatter, FormatterConfig}]]);
        {error, {already_started, _}} ->
            init2([Ident, Facility, [Level, {Formatter, FormatterConfig}]]);
        Error ->
            Error
    end.

%% @private
init2([Ident, Facility, [Level, {Formatter, FormatterConfig}]]) ->
    case syslog:open(Ident, [pid], Facility) of
        ok ->
            case lists:member(Level, ?LEVELS) of
				true ->
					{ok, #state{level=lager_util:level_to_num(Level),
								formatter=Formatter,
								format_config=FormatterConfig}};
				_ ->
					{error, bad_log_level}
			end;
		Error ->
			Error
    end.


%% @private
handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    case lists:member(Level, ?LEVELS) of
        true ->
            {ok, ok, State#state{level=lager_util:level_to_num(Level)}};
        _ ->
            {ok, {error, bad_log_level}, State}
    end;
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log, Message}, #state{level=Level,formatter=Formatter,format_config=FormatConfig} = State) ->
    case lager_util:is_loggable(Message, Level, ?MODULE) of
        true ->
			syslog:log(lager_msg:severity_as_int(Message), [Formatter:format(Message, FormatConfig)]),
            {ok, State};
        false ->
            {ok, State}
    end;
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
	application:stop(syslog),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
