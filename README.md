egeosypex
=====

Erlang library for Sypex Geolocation databases.
Supports Sypex Geo City in utf-8 encoding.

Read more about the data: http://sypexgeo.net


Likely you would use a pool of gen_server
processes for access to this API.

Build
-----

    $ rebar3 compile


Example
-------

```erlang
{ok, Data} = file:read_file("priv/SxGeoCity.dat").
{ok, Meta} = egeosypex:meta(Data).
{ok,{#{<<"id">> => 48,
       <<"iso">> => <<"CN">>,
       <<"lat">> => {decimal,3500,2},
       <<"lon">> => {decimal,10500,2},
       <<"name_en">> => <<"China">>,
       <<"name_ru">> => <<208,154,208,184,209,130,208,176,208,185>>},
     #{<<"country_id">> => 48,
       <<"id">> => 1816670,
       <<"lat">> => {decimal,3990750,5},
       <<"lon">> => {decimal,11639723,5},
       <<"name_en">> => <<"Beijing">>,
       <<"name_ru">> => <<208,159,208,181,208,186,208,184,208,189>>,
       <<"region_seek">> => 29082},
     #{<<"country_seek">> => 7932,
       <<"id">> => 2038349,
       <<"iso">> => <<"CN-11">>,
       <<"name_en">> => <<"Beijing Shi">>,
       <<"name_ru">> => <<208,159,208,181,208,186,208,184,208,189>>}}}
        = egeosypex:lookup({1,8,36,0}, Meta).

not_found = egeosypex:lookup({127,0,0,1}, Meta).
```