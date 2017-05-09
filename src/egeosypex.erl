-module(egeosypex).
-export([meta/1, lookup/2]).
-include("egeosypex.hrl").


%%-define(BINARY_COPY(Val), Val)
-define(BINARY_COPY(Val), binary:copy(Val)).

%%include("SxGeo.php");
%%$SxGeo = new SxGeo('SxGeoCity.dat');
%%print_r($SxGeo->getCityFull("1.8.36.0"));


meta(Data) ->
	<<"SxG", Vsn:8/integer, Created:32/integer, Parser:8/integer,
	  Encoding:8/integer, FirstByteIndexElem:8/integer, MainIndexElem:16/integer,
	  Blocks:16/integer,
	  Ranges:32/integer, IDLen:8/integer, MaxRegionRecSize:16/integer,
	  MaxCityRecSize:16/integer, RegDataSize:32/integer, CityDataSize:32/integer,
	  MaxCountryRecSize:16/integer, CounttryDataSize:32/integer,
	  PackFormatSize:16/integer, Rest/binary>> = Data,


	SzFBI = 4 * FirstByteIndexElem,
	SzMI = 4 * MainIndexElem,
	<<Pack_:PackFormatSize/binary, FBIB:SzFBI/binary, MIB:SzMI/binary, Rest2/binary>> = Rest,
	Pack = [split_pack(Packed) || Packed <- binary:split(Pack_, <<0>>, [global])],
	FBI = [N || <<N:32/integer>> <= FBIB],
	MI = [N || <<N:32/integer>> <= MIB],

	IDBlockSize = IDLen + 3,
	SzCountry = Ranges * IDBlockSize,

	<<Countries:SzCountry/binary, Regions:RegDataSize/binary, Cities:CityDataSize/binary, _/binary>> = Rest2,

	{ok, #sypex_meta{
		vsn = Vsn,
		creation_time = Created,
		parser = Parser,
		encoding = Encoding,
		elems_in_first_bytex_index = FirstByteIndexElem,
		elems_in_main_index = MainIndexElem,
		blocks_in_single_elem = Blocks,
		ranges = Ranges,
		id_len = IDLen,
		block_len = IDBlockSize,
		max_region_rec_size = MaxRegionRecSize,
		max_city_rec_size = MaxCityRecSize,
		regions_size = RegDataSize,
		cities_size = CityDataSize,
		max_country_rec_size = MaxCountryRecSize,
		countries_size = CounttryDataSize,
		pack_format_descr_size = PackFormatSize,
		pack_format = list_to_tuple(Pack),
		first_byte_index = list_to_tuple(FBI),
		main_index = list_to_tuple(MI),
		city_data = Cities,
		region_data = Regions,
		country_data = Countries

	}}.


lookup({A, _B, _C, _D} = _IP,
	   #sypex_meta{elems_in_first_bytex_index = EI, pack_format = Pack} = _Meta) when A == 0; A == 127; A == 10; A >= EI; Pack == [] ->
	not_found;

lookup({A, B, C, D} = _IP,
	#sypex_meta{elems_in_first_bytex_index = EI,
				first_byte_index = FBI,
				blocks_in_single_elem = Blocks,
				ranges = Ranges,
				main_index = MainIndex,
				country_data = Countries,
				id_len = IDLen,
				block_len = BlockSize} = Meta) ->
	<<_:1/binary, B3IP/binary>> = WIP = <<A:8/integer, B:8/integer, C:8/integer, D:8/integer>>,
	Min_ = element(A, FBI),
	Max_ = element(A + 1, FBI),

	%{Min, Max} = ...
	if
		Max_ - Min_ > Blocks ->
			Part = search_idx(WIP, Min_ div Blocks, Max_ div Blocks - 1, MainIndex),
			Min = max(Min_, if
								Part > 0 -> Part * Blocks;
								true -> 0
							end),
			Max = min(Max_, if
								Part > EI -> Ranges;
								true -> (Part + 1) * Blocks
							end);

		true ->
			Min = Min_,
			Max = Max_

	end,

	ByteOffset = search_db(B3IP, Min, Max, BlockSize, Countries) * BlockSize - IDLen,
	<<_:ByteOffset/binary, Seek:24/integer, _/binary>> = Countries,
	seek_data(Seek, Meta ).


seek_data(0, _Meta) -> not_found;

seek_data(Seek,
		  #sypex_meta{countries_size = CountrySize,
			  max_country_rec_size = MaxCountry,
					  city_data = CityData,
			  pack_format = PackFormat}) when  Seek < CountrySize ->
	{ok, Country} = read_data(Seek, MaxCountry, CityData, pack_format(country, PackFormat)),
	{ok, {Country, undefined, undefined}};

seek_data(Seek,
		  #sypex_meta{
			  max_city_rec_size = MaxCity,
			  max_country_rec_size = MaxCountry,
			  city_data = CityData,
			  region_data = RegionData,
			  max_region_rec_size = MaxRegion,
			  pack_format = PackFormat} = _Meta) ->

	{ok, #{<<"region_seek">> := RS} = City} = read_data(Seek, MaxCity, CityData, pack_format(city, PackFormat)),
	{ok, #{<<"country_seek">> := CS} = Region} = read_data(RS, MaxRegion, RegionData, pack_format(region, PackFormat)),
	{ok, Country} = read_data(CS, MaxCountry, CityData, pack_format(country, PackFormat)),
	{ok, {Country, City, Region}}.

pack_format(country, PackFormat) -> element(1, PackFormat);
pack_format(region, PackFormat) -> element(2, PackFormat);
pack_format(city, PackFormat) -> element(3, PackFormat).

read_data(Seek, Max, DB, PackFormat) ->
	<<_:Seek/binary, Data:Max/binary, _/binary>> = DB,
	unpack(PackFormat, Data).

search_db(B3IP, Min_, Max, BlockSize, Countries) ->
	if
		Max - Min_ > 1 ->
			search_db_idx(B3IP, Min_, Max, BlockSize, Countries);
		true ->
			Min_ + 1
	end.




search_db_idx(B3IP, Min, Max, BlockSize, Countries) when (Max - Min) > 8 ->
	Offset = (Min + Max) bsr 1,
	ByteOffset = (Offset * BlockSize),
	<<_:ByteOffset/binary, Substr:3/binary, _/binary>> = Countries,
	if
		B3IP > Substr ->
			search_db_idx(B3IP, Offset, Max, BlockSize, Countries);
		true ->
			search_db_idx(B3IP, Min, Offset, BlockSize, Countries)
	end;

search_db_idx(_B3IP, Min, Max, _BlockSize, _Countries) when Min >= Max ->
	Min;

search_db_idx(B3IP, Min, Max, BlockSize, Countries) ->
	ByteOffset = (Min * BlockSize),
	<<_:ByteOffset/binary, Substr:3/binary, _/binary>> = Countries,
	if
		B3IP >= Substr ->
			search_db_idx(B3IP, Min + 1, Max, BlockSize, Countries);
		true ->
			Min
	end.




search_idx(WIP, Min, Max, MainIndex) when (Max - Min) > 8 ->
	Offset = (Min + Max) bsr 1,
	if
		WIP > element(Offset + 1, MainIndex) ->
			search_idx(WIP, Offset, Max, MainIndex);
		true ->
			search_idx(WIP, Min, Offset, MainIndex)
	end;

search_idx(_WIP, Min, Max, _MainIndex) when Min >= Max -> Min;

search_idx(WIP, Min, Max, MainIndex) when WIP > element(Min + 1, MainIndex) ->
	search_idx(WIP, Min + 1, Max, MainIndex);

search_idx(_WIP, Min, _Max, _MainIndex) ->
	Min.


split_pack(Bin) ->
	[list_to_tuple(binary:split(Elem, <<":">>)) || Elem <- binary:split(Bin, <<"/">>, [global])].



unpack(Format, Data) ->
	unpack(Format, Data, #{}).

unpack([], _Data, Acc) ->
	{ok, Acc};

unpack([{FormatOne, Key} | Format], Data, Acc) ->
	{Val, Data2} = unpack_one(FormatOne, Data),
	unpack(Format, Data2, Acc#{Key => Val}).


unpack_one(<<"t">>, Data) ->
	<<I:8/little-signed-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"T">>, Data) ->
	<<I:8/little-unsigned-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"S">>, Data) ->
	<<I:16/little-signed-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"S">>, Data) ->
	<<I:16/little-unsigned-integer, Data2/binary>> = Data,
	{I, Data2};


unpack_one(<<"m">>, Data) ->
	<<I:24/little-signed-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"M">>, Data) ->
	<<I:24/little-unsigned-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"i">>, Data) ->
	<<I:32/little-signed-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"I">>, Data) ->
	<<I:32/little-unsigned-integer, Data2/binary>> = Data,
	{I, Data2};

unpack_one(<<"f">>, Data) ->
	<<F:32/little-float, Data2/binary>> = Data,
	{F, Data2};

unpack_one(<<"d">>, Data) ->
	<<F:64/little-float, Data2/binary>> = Data,
	{F, Data2};

unpack_one(<<"b">>, Data) ->
	[Blob, Data2] = binary:split(Data, <<0>>),
	{?BINARY_COPY(Blob), Data2};


unpack_one(<<"c", NBin/binary>>, Data) ->
	N = binary_to_integer(NBin),
	<<S:N/binary, Data2/binary>> = Data,
	{?BINARY_COPY(S), Data2};

unpack_one(<<"n", NBin/binary>>, Data) ->
	N = binary_to_integer(NBin),
	<<I:16/little-unsigned-integer, Data2/binary>> = Data,
	{{decimal, I, N}, Data2};

unpack_one(<<"N", NBin/binary>>, Data) ->
	N = binary_to_integer(NBin),
	<<I:32/little-unsigned-integer, Data2/binary>> = Data,
	{{decimal, I, N}, Data2}.
