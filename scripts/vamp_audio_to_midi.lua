ardour {
	["type"] = "EditorAction",
	name = "Polyphonic Audio to MIDI",
	license     = "MIT",
	author      = "Ardour Team",
description = [[
Analyze audio from the selected audio region to a selected MIDI region.

A MIDI region on the target track will have to be created first (use the pen tool).

This script uses the Polyphonic Transcription VAMP plugin from Queen Mary Univ, London.
The plugin works best at 44.1KHz input sample rate, and is tuned for piano and guitar music. Velocity is not estimated.
]]
}

function factory () return function ()
	local sel = Editor:get_selection ()
	local sr = Session:nominal_frame_rate ()
	local tm = Session:tempo_map ()
	local vamp = ARDOUR.LuaAPI.Vamp ("libardourvampplugins:qm-transcription", sr)
	local midi_region
	local audio_regions = {}
	local start_time = Session:current_end_frame ()
	local end_time = Session:current_start_frame ()
	for r in sel.regions:regionlist ():iter () do
		if r:to_midiregion():isnil() then
			local st = r:position()
			local ln = r:length()
			local et = st + ln
			if st < start_time then
				start_time = st
			end
			if et > end_time then
				end_time = et
			end
			table.insert(audio_regions, r)
		else
			midi_region = r:to_midiregion()
		end
	end
	assert (audio_regions and midi_region)
	midi_region:set_initial_position(start_time)
	midi_region:set_length(end_time - start_time, 0)

	for i,ar in pairs(audio_regions) do
		local a_off = ar:position ()
		local b_off = midi_region:quarter_note () - midi_region:start_beats ()

		vamp:analyze (ar:to_readable (), 0, nil)
		local fl = vamp:plugin ():getRemainingFeatures ():at (0)
		if fl and fl:size() > 0 then
			local mm = midi_region:midi_source(0):model()
			local midi_command = mm:new_note_diff_command ("Audio2Midi")
			for f in fl:iter () do
				local ft = Vamp.RealTime.realTime2Frame (f.timestamp, sr)
				local fd = Vamp.RealTime.realTime2Frame (f.duration, sr)
				local fn = f.values:at (0)

				local bs = tm:exact_qn_at_frame (a_off + ft, 0)
				local be = tm:exact_qn_at_frame (a_off + ft + fd, 0)

				local pos = Evoral.Beats (bs - b_off)
				local len = Evoral.Beats (be - bs)
				local note = ARDOUR.LuaAPI.new_noteptr (1, pos, len, fn + 1, 0x7f)
				midi_command:add (note)
			end
			mm:apply_command (Session, midi_command)
		end
	end
end end

function icon (params) return function (ctx, width, height, fg)
	local txt = Cairo.PangoLayout (ctx, "ArdourMono ".. math.ceil(width * .7) .. "px")
	txt:set_text ("\u{2669}") -- quarter note symbol UTF8
	local tw, th = txt:get_pixel_size ()
	ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
	ctx:move_to (.5 * (width - tw), .5 * (height - th))
	txt:show_in_cairo_context (ctx)
end end
