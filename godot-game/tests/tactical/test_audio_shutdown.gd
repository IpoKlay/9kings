extends SceneTree
const Shutdown=preload('res://tests/tactical/helpers/native_shutdown.gd')
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:
		failures+=1
		push_error(note)
func run():
	# Repeatedly exercise actual audio ownership, without loading game assets or
	# retaining a strong reference to the resource we expect the mixer to release.
	for cycle in 8:
		var player=AudioStreamPlayer.new()
		var stream
		stream=AudioStreamWAV.new()
		stream.format=AudioStreamWAV.FORMAT_8_BITS
		stream.mix_rate=44100
		var samples=PackedByteArray()
		samples.resize(44100)
		stream.data=samples
		if '--game-audio' in OS.get_cmdline_user_args():
			stream=null
			# Load afresh so the test itself does not retain the expected resource.
			stream=load('res://assets/selected_audio/horn.wav' if cycle%2==0 else 'res://assets/music/crusade.mp3')
		root.add_child(player)
		player.stream=stream
		player.play()
		var stream_ref=weakref(stream)
		var playback_ref=weakref(player.get_stream_playback())
		var player_ref=weakref(player)
		check(playback_ref!=null,'Real playback was created')
		player.stop()
		player.stream=null
		player.queue_free()
		stream=null
		await Shutdown.settle(self)
		check(player_ref.get_ref()==null,'Player freed in cycle %d'%cycle)
		check(stream_ref.get_ref()==null,'Stream released in cycle %d'%cycle)
		check(playback_ref!=null and playback_ref.get_ref()==null,'Playback released in cycle %d'%cycle)
	print('AUDIO SHUTDOWN: 8 cycles, %d failures'%failures)
	quit(1 if failures else 0)
