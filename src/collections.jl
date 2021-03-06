
# Not only filter on antenna-names, but also return `cal` appropriate [nants, npoln, nchan]
function collectAntennaWeights(
	io::IO,
	ant_name_filter::Array{String, 1},
	channel_range::UnitRange
)::Array{ComplexF64, 3}
	antweights = AntennaWeights(io)
	ant_indices = [findfirst(x -> x == name, antweights.names) for name in ant_name_filter]

	return permutedims(
		antweights.weights[:, channel_range, ant_indices],
		[3, 1, 2]
	)
end

function collectTelinfo(telinfoDict::Dict)::TelInfo
	collectTelinfo(telinfoDict, Vector{String}())
end

function collectTelinfo(telinfoDict::Dict, ant_name_filter::Array{String, 1})::TelInfo
	telinfo = TelInfo()
	default_diameter = get(telinfoDict, "antenna_diameter", 0.0)

	for antinfo in values(telinfoDict["antennas"])
		if length(ant_name_filter) == 0 || antinfo["name"] in ant_name_filter
			push!(telinfo.antenna_names, antinfo["name"])
			push!(telinfo.antenna_numbers, antinfo["number"])
			push!(telinfo.antenna_diameters, "diameter" in keys(antinfo) ? antinfo["diameter"] : default_diameter)
			telinfo.antenna_positions = cat(telinfo.antenna_positions, antinfo["position"], dims=2)
		end
	end

	telinfo.antenna_position_frame = telinfoDict["antenna_position_frame"]
	telinfo.latitude = isa(telinfoDict["latitude"], String) ? dms2deg(telinfoDict["latitude"]) : telinfoDict["latitude"]
	telinfo.longitude = isa(telinfoDict["longitude"], String) ? dms2deg(telinfoDict["longitude"]) : telinfoDict["longitude"]
	telinfo.altitude = telinfoDict["altitude"]
	telinfo.telescope_name = telinfoDict["telescope_name"]
	return telinfo
end

function collectDimBeamObsInfo(header::GuppiRaw.Header)
	# infer number of beams
	beaminfo = BeamInfo()
	nbeams = 0
	while @sprintf("RA_OFF%01d",nbeams) in keys(header)
		push!(beaminfo.src_names, @sprintf("BEAM_%01d", nbeams))
		push!(beaminfo.ras, header[@sprintf("RA_OFF%01d", nbeams)])
		push!(beaminfo.decs, header[@sprintf("DEC_OFF%01d", nbeams)])
		nbeams += 1
	end
	if nbeams == 0 
		push!(beaminfo.src_names, "BEAM_BORESIGHT")
		push!(beaminfo.ras, header["RA_STR"])
		push!(beaminfo.decs, header["DEC_STR"])
		nbeams = 1
	end

	diminfo = DimInfo()
	diminfo.npol, diminfo.ntimes, diminfo.nchan, diminfo.nants = size(header)
	diminfo.nbeams = nbeams

	
	obsinfo = ObsInfo()
	obsinfo.obsid = header["SRC_NAME"]
	obsinfo.freq_array = [(header["SCHAN"] + 0.5 + chan)*header["CHAN_BW"] for chan in 0:diminfo.nchan-1]
	obsinfo.phase_center_ra = header["RA_STR"]
	obsinfo.phase_center_dec = header["DEC_STR"]
	obsinfo.instrument_name = get(header, "TELESCOP", "Unknown")

	return diminfo, beaminfo, obsinfo
end

function collectObsAntnames(header::GuppiRaw.Header)
	obs_antenna_names = Array{String, 1}()
	antnmes_index = 0
	while @sprintf("ANTNMS%02d", antnmes_index) in keys(header)
		append!(obs_antenna_names, split(header[@sprintf("ANTNMS%02d", antnmes_index)], ','))
		antnmes_index += 1
	end

	return map(antlo -> antlo[1:end-1], obs_antenna_names)
end