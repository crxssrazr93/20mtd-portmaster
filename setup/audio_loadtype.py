"""Stream the music instead of decoding it into RAM at load.

Every clip in the game is Vorbis with load type DecompressOnLoad, so the player decodes the two
music loops (110 s and 72 s of 44.1 kHz stereo) into PCM when their scene loads. Clips longer
than STREAM_FROM seconds get load type Streaming (2): decoded while playing, read from the
.resource file. Only m_LoadType changes; the Vorbis data is untouched. The sound effects (6 s at
most) stay as they are, since decoding them once is cheapest to play.

Usage: python audio_loadtype.py <Data dir> [STREAM_FROM=30]   (in place)
"""
import os, sys, UnityPy

DECOMPRESS, STREAMING = 0, 2
FILES = ['sharedassets0.assets', 'sharedassets1.assets']


def main():
    data = sys.argv[1]
    stream_from = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
    for name in FILES:
        path = os.path.join(data, name)
        env = UnityPy.load(path)
        streamed = []
        for o in env.objects:
            if o.type.name != 'AudioClip':
                continue
            t = o.read_typetree()
            if t['m_LoadType'] == DECOMPRESS and t['m_Length'] > stream_from:
                t['m_LoadType'] = STREAMING
                o.save_typetree(t)
                streamed.append(t['m_Name'])
        if streamed:
            out = list(env.files.values())[0].save()
            with open(path + '.tmp', 'wb') as fh:
                fh.write(out)
            os.replace(path + '.tmp', path)
        print(f'audio {name}: streaming {streamed}', flush=True)


if __name__ == '__main__':
    main()
