using System;
using System.Linq;
using System.Numerics;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using System.IO;

namespace Slotter
{
    public sealed class SemanticVersion : IComparable<SemanticVersion>
    {
        readonly BigInteger[] core;
        readonly string[] prerelease;
        SemanticVersion(BigInteger[] core, string[] prerelease) { this.core = core; this.prerelease = prerelease; }
        public static SemanticVersion Parse(string value)
        {
            Match m = Regex.Match(value ?? "", @"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?\z", RegexOptions.CultureInvariant);
            if (!m.Success) throw new FormatException("Invalid semantic version: " + value);
            string[] pre = m.Groups[4].Success ? m.Groups[4].Value.Split('.') : Array.Empty<string>();
            if (pre.Any(p => p.All(char.IsDigit) && p.Length > 1 && p[0] == '0')) throw new FormatException("Leading zero in prerelease version.");
            return new SemanticVersion(new[] { BigInteger.Parse(m.Groups[1].Value), BigInteger.Parse(m.Groups[2].Value), BigInteger.Parse(m.Groups[3].Value) }, pre);
        }
        public int CompareTo(SemanticVersion other)
        {
            for (int i = 0; i < 3; i++) { int c = core[i].CompareTo(other.core[i]); if (c != 0) return c; }
            if (prerelease.Length == 0 || other.prerelease.Length == 0) return (prerelease.Length == 0 ? 1 : 0).CompareTo(other.prerelease.Length == 0 ? 1 : 0);
            for (int i = 0; i < Math.Min(prerelease.Length, other.prerelease.Length); i++)
            {
                bool a = prerelease[i].All(c => c >= '0' && c <= '9'), b = other.prerelease[i].All(c => c >= '0' && c <= '9');
                BigInteger an = a ? BigInteger.Parse(prerelease[i]) : BigInteger.Zero, bn = b ? BigInteger.Parse(other.prerelease[i]) : BigInteger.Zero;
                int c = a && b ? an.CompareTo(bn) : a != b ? (a ? -1 : 1) : string.CompareOrdinal(prerelease[i], other.prerelease[i]);
                if (c != 0) return c;
            }
            return prerelease.Length.CompareTo(other.prerelease.Length);
        }
    }

    public sealed class UpdateRelease
    {
        public string Version { get; init; }
        public Uri Url { get; init; }
        public string Sha256 { get; init; }
    }

    public static class UpdateFeed
    {
        public const string ProductionUrl = "https://kalkmancode.co.uk/slotter/appcast.xml";
        public const string SparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle";
        public const string SlotterNamespace = "https://kalkmancode.co.uk/slotter/appcast";
        public static void ValidateUrl(Uri url, bool localTest)
        {
            if (url == null || !url.IsAbsoluteUri || url.UserInfo.Length != 0 ||
                !(url.Scheme == "https" || (localTest && url.Scheme == "http" && url.IsLoopback)))
                throw new InvalidDataException("Updates require HTTPS; an explicit feed override also permits loopback HTTP.");
        }
        public static UpdateRelease Select(string xml, bool localTest)
        {
            XNamespace sparkle = SparkleNamespace, slotter = SlotterNamespace;
            using var reader = XmlReader.Create(new StringReader(xml), new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 2 * 1024 * 1024 });
            XDocument doc = XDocument.Load(reader);
            UpdateRelease latest = null;
            foreach (XElement enclosure in doc.Descendants("item").Elements("enclosure"))
            {
                if ((string)enclosure.Attribute(sparkle + "os") != "windows") continue;
                string version = (string)enclosure.Attribute(sparkle + "shortVersionString") ?? (string)enclosure.Parent.Element(sparkle + "shortVersionString");
                SemanticVersion parsed;
                try { parsed = SemanticVersion.Parse(version); } catch (FormatException) { continue; }
                string hash = (string)enclosure.Attribute(slotter + "sha256");
                if (!Regex.IsMatch(hash ?? "", "^[a-fA-F0-9]{64}$")) throw new InvalidDataException("Windows update has no valid SHA-256 checksum.");
                if (!Uri.TryCreate((string)enclosure.Attribute("url"), UriKind.Absolute, out Uri url)) throw new InvalidDataException("Windows update URL is invalid.");
                ValidateUrl(url, localTest);
                if (latest == null || parsed.CompareTo(SemanticVersion.Parse(latest.Version)) > 0)
                    latest = new UpdateRelease { Version = version, Url = url, Sha256 = hash.ToLowerInvariant() };
            }
            return latest;
        }
    }
}
