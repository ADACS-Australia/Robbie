#! /usr/bin/env python
from __future__ import print_function

from astropy.table import Table
import dateutil
import dateutil.parser
import numpy as np
import matplotlib
from matplotlib import pyplot
import sqlite3
import argparse
import sys
import os

__author__ = ["Paul Hancock"]
__date__ = '2019/08/19'


def plot_summary(cur, plotfile):
    """
    Create a summary plot for all sources, identifying which are likely to be variable.

    parameters
    ----------
    cur : sqlite3.connection.cursor
        DB connection
    plotfile : str
        Filename for the output plot file.
    """
    cur.execute("""SELECT pval_peak_flux, md, abs(mean_peak_flux) FROM stats WHERE pval_peak_flux >0""")
    rows = cur.fetchall()

    pval_peak_flux, md, mean_peak_flux = list(map(np.array, zip(*rows)))

    kwargs = {'fontsize':14}
    fig = pyplot.figure(figsize=(5,8))


    ax = fig.add_subplot(1,1,1)
    cax = ax.scatter(md, np.log10(pval_peak_flux), c = np.log10(mean_peak_flux), cmap=matplotlib.cm.viridis_r)
    cb = fig.colorbar(cax,ax=ax)
    cb.set_label("log10(Peak flux in epoch 1) (Jy)", **kwargs)

    ax.set_ylim((-11,1.001))
    ax.set_xlim((-0.3,0.3))
    ax.set_ylabel("log(p_val)", **kwargs)
    ax.set_xlabel("Debiased modulation index ($m_d$)", **kwargs)
    ax.axhline(-3, c='k')
    ax.axvline(0.05, c='k')
    ax.text(0.1, -5, "variable", **kwargs)
    ax.fill_between([-0.3,0.05],-25, y2=2, color='k', alpha=0.2)
    ax.fill_betweenx([-3,2],0.05, x2=0.3, color='k', alpha=0.2)
    ax.text(-0.25, -5, "not variable", **kwargs)
    pyplot.savefig(plotfile)
    return


def plot_lc(cur, dates=False):
    """
    Create individual light curve plots.
    Each plot is saved to plots/uuid.png

    parameters
    ----------
    cur : sqlite3.connection.cursor
        DB connection
    """
    cur.execute("""SELECT DISTINCT uuid FROM sources""")
    sources = cur.fetchall()

    for src in sources:
        uuid = src[0]
        fname = 'plots/{0}.png'.format(uuid)
        print(fname, end='')
        if os.path.exists(fname):
            print(" ... skip")
            continue

        cur.execute(""" SELECT peak_flux, err_peak_flux, s.epoch, date 
        FROM sources s JOIN epochs e 
        ON s.epoch = e.epoch WHERE uuid=?
        ORDER BY e.epoch """, (uuid,))
        peak_flux, err_peak_flux, epoch, date = map(np.array, zip(*cur.fetchall()))
        cur.execute("""SELECT m, md, chisq_peak_flux FROM stats WHERE uuid=? """, (uuid,))
        m, md, chisq_peak_flux = cur.fetchone()

        if dates:
            try:
                epoch = [dateutil.parser.parse(d) for d in date]
            except ValueError as e:
                print(" ... Unknown date encountered, reverting to epoch plotting", end='')
                dates = False
        pyplot.clf()
        s = 'm={0:5.3f}\nmd={1:4.2f}\nchisq={2:4.1f}'.format(m, md, chisq_peak_flux)
        pyplot.errorbar(epoch, peak_flux, yerr=err_peak_flux, label=s)
        pyplot.ylabel('Flux Density (Jy/Beam)')
        if not dates:
            pyplot.xlabel('Epoch')
        pyplot.title('{0}'.format(uuid))
        pyplot.legend()
        pyplot.savefig(fname)
        print(" ... done")
    return

def plot_summary_table(filename, plotfile):
    """
    Create a summary plot for all sources, identifying which are likely to be variable.

    parameters
    ----------
    filename : str
        Input table filename
    plotfile : str
        Filename for the output plot file
    """
    tab = Table.read(filename)
    pval_peak_flux = tab['pval_peak_flux']
    md = tab['md']
    mean_peak_flux = tab['mean_peak_flux']

    kwargs = {'fontsize':14}
    fig = pyplot.figure(figsize=(5,8))


    ax = fig.add_subplot(1,1,1)
    cax = ax.scatter(md, np.log10(pval_peak_flux), c = np.log10(mean_peak_flux), cmap=matplotlib.cm.viridis_r)
    cb = fig.colorbar(cax,ax=ax)
    cb.set_label("log10(Peak flux in epoch 1) (Jy)", **kwargs)

    ax.set_ylim((-11,1.001))
    ax.set_xlim((-0.3,0.3))
    ax.set_ylabel("log(p_val)", **kwargs)
    ax.set_xlabel("Debiased modulation index ($m_d$)", **kwargs)
    ax.axhline(-3, c='k')
    ax.axvline(0.05, c='k')
    ax.text(0.1, -5, "variable", **kwargs)
    ax.fill_between([-0.3,0.05],-25, y2=2, color='k', alpha=0.2)
    ax.fill_betweenx([-3,2],0.05, x2=0.3, color='k', alpha=0.2)
    ax.text(-0.25, -5, "not variable", **kwargs)
    pyplot.savefig(plotfile)
    return

def plot_lc_table(flux_table, stats_table):
    """
    Create individual light curve plots.
    Each plot is saved to plots/uuid.png

    parameters
    ----------
    filename : str
        Filename of the flux table
    """
    ftab = Table.read(flux_table)
    stab = Table.read(stats_table)
    fluxes = [a for a in ftab.colnames if a.startswith('peak_flux')]
    err_fluxes = [a for a in ftab.colnames if a.startswith('err_peak_flux')]
    epoch = list(range(len(fluxes)))
    for row in ftab:
        fname = 'plots/{0}.png'.format(row['uuid'])
        print(fname, end='')
        if os.path.exists(fname):
            print(" ... skip")
            continue
        srow = stab[stab['uuid'] == row['uuid']]

        pyplot.clf()
        s = 'm={0:5.3f}\nmd={1:4.2f}\nchisq={2:4.1f}'.format(
             srow['m'][0], srow['md'][0], srow['chisq_peak_flux'][0])
        pyplot.errorbar(epoch, list(row[fluxes]), yerr=list(row[err_fluxes]), label=s)
        pyplot.ylabel('Flux Density (Jy/Beam)')
        pyplot.xlabel('Epoch')
        pyplot.title('{0}'.format(row['uuid']))
        pyplot.legend()
        pyplot.savefig(fname)
        print(" ... done")
    return
       


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    group1 = parser.add_argument_group("Create a variability plot")
    group1.add_argument("--dbname", dest='db', type=str, default=None,
                        help="The input database")
    group1.add_argument("--ftable", dest='ftable', type=str, default=None,
                        help="flux table")
    group1.add_argument("--stable", dest='stable', type=str, default=None,
                        help="stats table")
    group1.add_argument("--plot", dest='plotfile', type=str, default=None,
                        help="output plot")
    group1.add_argument("--all", dest='all', action='store_true', default=False,
                        help="Also plot individual light curves. Default:False")
#    group1.add_argument("--dates", dest='dates', action='store_true', default=False,
#                        help="Individual plots have date on the horizontal axis.")

    results = parser.parse_args()


    if results.db:
        conn = sqlite3.connect(results.name)
        cur = conn.cursor()
        plot_summary(cur=cur, plotfile=results.plotfile)
        if results.all:
            plot_lc(cur=cur, dates=results.dates)
        conn.close()
    elif results.ftable or results.stable:
        if not (results.ftable and results.stable):
            print("ERROR: --stable and --ftable are both required, only one supplied.")
        plot_summary_table(results.stable, results.plotfile)
        if results.all:
            plot_lc_table(results.ftable, results.stable)
    else:
        parser.print_help()
        sys.exit()

