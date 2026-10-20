// Compile against the ORIGINAL, pinned DJ Library src/BridgeSnapshot.cs.
// Input files are generated on the same runner by REAL bridge C++ contract tests.
// No installed foobar, audio, actual profile, network, or credentials are used.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace DJLibrary
{
    // Pure compile-only data carrier with precisely the setters the original reader uses.
    public sealed class DigitalItem
    {
        public int ItemId { get; set; }
        public string Path { get; set; }
        public int Subsong { get; set; }
        public string Artist { get; set; }
        public string Title { get; set; }
        public string OriginalTitle { get; set; }
        public string RemixedBy { get; set; }
        public string Album { get; set; }
        public string AlbumArtist { get; set; }
        public string Genre { get; set; }
        public string Style { get; set; }
        public double Bpm { get; set; }
        public string Label { get; set; }
        public string Catalog { get; set; }
        public double DurationSeconds { get; set; }
        public string Codec { get; set; }
        public string Bitrate { get; set; }
        public string Fingerprint { get; set; }
        public string MetadataVectorsJson { get; set; }
    }

    internal static class BridgeProducerConsumerInterop
    {
        private static void Must(bool ok, string message)
        {
            if (!ok) throw new InvalidDataException("Original Bridge producer/consumer: " + message);
        }

        private static string Dir(string root, string name)
        {
            return System.IO.Path.Combine(root, name);
        }

        private static void CheckV3Vectors(string json)
        {
            Must(!String.IsNullOrWhiteSpace(json), "v3 lossless vectors missing");
            using (JsonDocument parsed = JsonDocument.Parse(json))
            {
                JsonElement root = parsed.RootElement;
                Must(root.ValueKind == JsonValueKind.Array && root.GetArrayLength() == 6,
                    "canonical C++-produced vector count");
                var fields = root.EnumerateArray().ToDictionary(
                    x => x.GetProperty("name").GetString(),
                    x => x.GetProperty("values"));
                Must(fields.Count == 6, "canonical vector distinct-case names");
                Must(fields["MOOD"].GetArrayLength() == 2 &&
                    fields["MOOD"][0].GetString() == "Euphoric" &&
                    fields["MOOD"][1].GetString() == "Dark",
                    "multi-valued MOOD lost or reordered");
                Must(fields["EMPTY"].GetArrayLength() == 1 &&
                    fields["EMPTY"][0].GetString() == "",
                    "empty metadata value lost");
                Must(fields["Quoted"].GetArrayLength() == 2 &&
                    fields["Quoted"][0].GetString() == "A\"B" &&
                    fields["Quoted"][1].GetString() == "Line\nBreak",
                    "JSON quotes/newline escape did not round-trip");
                Must(fields["GENRE"].GetArrayLength() == 1 &&
                    fields["GENRE"][0].GetString() == "House",
                    "core-tag vectors missing");
                Must(fields.ContainsKey("custom_tag") &&
                    fields.ContainsKey("CUSTOM_TAG"),
                    "case-preserved producer metadata keys lost");
            }
        }

        private static void CheckValid(string root, int schema)
        {
            string dir = Dir(root, schema == 3 ? "v3" : "v2");
            BridgeSnapshotStatus status = BridgeSnapshotReader.Inspect(dir, true);
            Must(status.Present && status.Complete && status.Compatible &&
                status.SchemaVersion == schema && status.DeclaredItemCount == 3 &&
                status.VerifiedItemCount == 3 && status.Generation == 7 &&
                status.SourceId == "ci-bridge-source-only" &&
                String.IsNullOrEmpty(status.Error), "producer status schema " + schema);

            List<DigitalItem> items = BridgeSnapshotReader.LoadItems(dir, status);
            Must(items.Count == 3, "number of records");
            var fingerprints = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < 3; i++)
            {
                DigitalItem d = items[i];
                Must(d.ItemId == i + 1 && d.Subsong == i &&
                    d.Path == @"C:\Music\test.flac" &&
                    d.Artist == "Artist" && d.Title == "Title " + i &&
                    d.Album == "Album" && d.Genre == "Trance" &&
                    d.DurationSeconds == 300 && d.Codec == "FLAC" &&
                    d.Bitrate == "900" && d.Bpm == 0,
                    "original C++ producer values and identity on row " + i);
                Must(d.Fingerprint != null && d.Fingerprint.Length == 16 &&
                    fingerprints.Add(d.Fingerprint),
                    "distinct deterministic native producer fingerprints");
                if (schema == 3) CheckV3Vectors(d.MetadataVectorsJson);
                else Must(String.IsNullOrEmpty(d.MetadataVectorsJson),
                    "v2 unexpectedly exposes v3 metadata vectors");
            }
            Console.WriteLine("PASS real C++ producer -> original DJ Library consumer v" + schema +
                ", 3 track identities, fields, fingerprints" +
                (schema == 3 ? ", six canonical multivalue metadata vectors" : ""));
        }

        private static void CheckRejected(string root, string fixtureName, bool expectIncomplete)
        {
            BridgeSnapshotStatus status = BridgeSnapshotReader.Inspect(Dir(root, fixtureName), true);
            Must(status.Present && (!status.Compatible || !status.Complete) &&
                (!expectIncomplete || !status.Complete),
                "invalid " + fixtureName + " snapshot incorrectly authoritative");
            bool denied = false;
            try { BridgeSnapshotReader.LoadItems(Dir(root, fixtureName), status); }
            catch (InvalidDataException) { denied = true; }
            Must(denied, "invalid " + fixtureName + " must not enter the consumer");
            Console.WriteLine("PASS C# reader rejected real C++ fixture " + fixtureName);
        }

        public static int Main(string[] args)
        {
            try
            {
                Must(Environment.GetEnvironmentVariable("GITHUB_ACTIONS") == "true" &&
                    Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT") == "github-hosted" &&
                    args.Length == 1,
                    "disposable public GitHub runner and one fixture argument required");
                string root = Path.GetFullPath(args[0]);
                string workspace = Environment.GetEnvironmentVariable("GITHUB_WORKSPACE");
                Must(!String.IsNullOrWhiteSpace(workspace) &&
                    root.StartsWith(
                        Path.GetFullPath(workspace).TrimEnd(Path.DirectorySeparatorChar) +
                        Path.DirectorySeparatorChar, StringComparison.Ordinal) &&
                    Path.GetFileName(root) == "snapshot-verifier-fixtures",
                    "fixture root must be generated under GitHub workspace");
                Must(File.Exists(Path.Combine(root, "v3", "bridge-state.tsv")) &&
                    File.Exists(Path.Combine(root, "v3", "digital-items.tsv.gz")),
                    "actual source-generated gzip and state files required");

                BridgeSnapshotReader.ValidateSchemaV3Contract();
                CheckValid(root, 3);
                CheckValid(root, 2);
                CheckRejected(root, "wrong-count", false);
                CheckRejected(root, "incomplete", true);
                CheckRejected(root, "future-schema", false);
                CheckRejected(root, "wrong-header", false);
                Console.WriteLine("PASS end-to-end C++ bridge schema-v3 producer -> real " +
                    "DJ Library BridgeSnapshotReader, with v2 and negative cases");
                return 0;
            }
            catch (Exception e)
            {
                Console.Error.WriteLine("FAIL Bridge C++ -> C# consumer: " + e);
                return 1;
            }
        }
    }
}
