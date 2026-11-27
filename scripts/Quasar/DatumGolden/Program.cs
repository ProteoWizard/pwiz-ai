// Prints datum's EMG outputs on fixed inputs, so Quasar's port can be pinned to them.
// The inputs are built with the same expressions as Quasar.Test/EmgTest.cs.
using System;
using System.Globalization;
using System.Reflection;
using Datum.Core.Algorithms;
using Datum.Core.Algorithms.BackgroundSubtractors;
using Datum.Core.Algorithms.Integrators;

static class Program
{
    static MethodInfo _unitDensity;
    static MethodInfo _fit;
    static MethodInfo _crossings;

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var emgFit = typeof(ConsensusEmgIntegrator).Assembly.GetType("Datum.Core.Algorithms.Integrators.EmgFit");
        _unitDensity = emgFit.GetMethod("UnitDensity", BindingFlags.Public | BindingFlags.Static);
        _fit = emgFit.GetMethod("Fit", BindingFlags.Public | BindingFlags.Static);
        _crossings = emgFit.GetMethod("HeightCrossings", BindingFlags.Public | BindingFlags.Static);

        // Case A: one tailed EMG with a fixed integer "noise" pattern.
        int n = 60;
        var rt = Grid(n);
        var y = new double[n];
        for (int i = 0; i < n; i++)
            y[i] = 1500.0 * Unit(12.0, 0.25, 0.35, rt[i]) + ((i * 37) % 11 - 5) * 3.0;
        object fit = _fit.Invoke(null, new object[] { rt, y });
        Print("A.Area", Prop(fit, "Area"));
        Print("A.Mu", Prop(fit, "Mu"));
        Print("A.Sigma", Prop(fit, "Sigma"));
        Print("A.Tau", Prop(fit, "Tau"));

        // Case B: six traces sharing one EMG, interference on the first two.
        double[] rel = { 1.0, 0.8, 0.6, 0.5, 0.45, 0.34 };
        int nb = 120;
        var rtb = Grid(nb);
        var frags = new double[rel.Length][];
        for (int f = 0; f < rel.Length; f++)
        {
            frags[f] = new double[nb];
            for (int i = 0; i < nb; i++)
            {
                frags[f][i] = rel[f] * 1000.0 * Unit(12.0, 0.25, 0.35, rtb[i]);
                if (f < 2)
                {
                    double d = rtb[i] - 12.5;
                    frags[f][i] += 600.0 * Math.Exp(-(d * d) / (2.0 * 0.18 * 0.18));
                }
            }
        }
        var bounds = new PeakBounds(true, 0, nb - 1, nb / 2, rtb[0], rtb[nb - 1], 12.0);
        double[] areas = new ConsensusEmgIntegrator().IntegrateAll(rtb, frags, bounds, IntegratorOptions.Default);
        for (int f = 0; f < areas.Length; f++)
            Print("B.Area" + f, areas[f]);

        // Case C: height crossings.
        foreach (double fraction in new[] { 0.05, 0.5 })
        {
            var lr = ((double, double))_crossings.Invoke(null, new object[] { 12.0, 0.25, 0.35, fraction });
            Print("C.Left" + fraction, lr.Item1);
            Print("C.Right" + fraction, lr.Item2);
        }

        // Case D: linear baseline between off-grid boundaries on case A plus a sloped offset.
        var yd = new double[n];
        for (int i = 0; i < n; i++)
            yd[i] = y[i] + 50.0 + 3.0 * i;
        double startRt = rt[10] + 0.013, endRt = rt[50] - 0.021;
        var bd = new PeakBounds(true, 10, 50, 30, startRt, endRt, rt[30]);
        double[] sub = new LinearBaselineSubtractor().Subtract(rt, yd, bd);
        double sum = 0.0;
        foreach (double v in sub)
            sum += v;
        Print("D.Sum", sum);
        Print("D.Value10", sub[10]);
        Print("D.Value30", sub[30]);
        Print("D.Value55", sub[55]);
    }

    static double[] Grid(int n)
    {
        var rt = new double[n];
        for (int i = 0; i < n; i++)
            rt[i] = 9.0 + 7.0 * i / (n - 1);
        return rt;
    }

    static double Unit(double mu, double sigma, double tau, double t)
    {
        return (double)_unitDensity.Invoke(null, new object[] { mu, sigma, tau, t });
    }

    static double Prop(object o, string name)
    {
        return (double)o.GetType().GetProperty(name).GetValue(o);
    }

    static void Print(string name, double v)
    {
        Console.WriteLine(name + " = " + v.ToString("R", CultureInfo.InvariantCulture));
    }
}
