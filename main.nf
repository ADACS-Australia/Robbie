#! /usr/bin/env nextflow

nextflow.enable.dsl=2

author = "Paul Hancock"
version = "2.2.0"
prev_git_hash = "7d6c6"
date = "2022-02-24"
/* CONFIGURATION STAGE */

/* for executing without a container */
params.codeDir = "${baseDir}/"
params.stilts = "stilts"

// output directory
params.output_dir = "${baseDir}/results/"

// input images are listed in this file, one image per line
params.image_file = "$baseDir/images.txt"

// Warping stage
params.warp = true
params.ref_catalogue = "$baseDir/master.fits"
params.refcat_ra = 'ra'
params.refcat_dec = 'dec'

// Plotting params
params.by_epoch = true

// monitoring of a pre-determined source
params.use_monitoring_src_file = false
params.monitoring_src_file = ""

// Source finding region file
params.use_region_file = false
params.region_file = ""


log.info """\
         ROBBIE the Space Detective
         ==========================
         version      : ${version} (${prev_git_hash}) - ${date}
         images from  : ${params.image_file}
         do warping   : ${params.warp}
         warp ref cat : ${params.ref_catalogue}
         minotor src  : ${params.use_monitoring_src_file} / ${params.monitoring_src_file}
         region file  : ${params.use_region_file} / ${params.region_file}
         output to    : ${params.output_dir}
         --
         run as       : ${workflow.commandLine}
         config files : ${workflow.configFiles}
         container    : ${workflow.containerEngine}:${workflow.container}
         """
         .stripIndent()

// Read the image names from a text file
image_ch = Channel
  .fromPath(params.image_file)
  .splitText()
  .map{ it -> tuple(file(it).baseName, file(it.trim()))}

// Set up optional commands
if ( params.use_monitoring_src_file ) {
  monitoring_src_file = Channel.fromPath( params.monitoring_src_file )
  monitoring_command = "${params.stilts} tcatn nin=2 in1=mean_comp.fits in2=${monitoring_src_file} out=persistent_sources.fits ofmt=fits"
}
else {
  monitoring_command =  "mv *_comp.fits persistent_sources.fits"
}
if ( params.use_region_file ) {
  region_file = Channel.fromPath( params.region_file )
  region_command = "--region ${region_file}"
}
else {
  region_command = ""
}


process bane_raw {
  label 'bane'

  input:
  tuple val(basename), path(image)

  output:
  tuple val(basename), path(image), path("*_{bkg,rms}.fits")

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  BANE --cores ${task.cpus} ${image}
  """
}


process initial_sfind {
  label 'aegean'

  input:
  tuple val(basename), path(image), path(bkg_rms_fits)

  output:
  tuple val(basename), path('*.fits', includeInputs:true)

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  aegean --cores ${task.cpus} --background *_bkg.fits --noise *_rms.fits --table ${image} ${region_command} ${image}
  ls *.fits
  """
}


process fits_warp {
  label 'warp'

  input:
  tuple val(basename), path(initial_catalogue)
  each ref_catalogue

  output:
  path "*_warped.fits"
  tuple val("${basename}_warped"), path("*.fits", includeInputs:true)

  script:
  suff1=(params.refcat_ra=='ra' ? '_1':'')
  suff2=(params.refcat_ra=='ra' ? '_2':'')

  if (params.warp == true)
  """
  echo ${task.process} on \${HOSTNAME}
  fits_warp.py --cores ${task.cpus} --refcat ${ref_catalogue} --incat ${basename}_comp.fits \
               --ra1 ra --dec1 dec --ra2 ${params.refcat_ra} --dec2 ${params.refcat_dec} \
               --xm ${basename}_xm.fits
  fits_warp.py --infits ${basename}.fits --xm ${basename}_xm.fits --suffix warped \
               --ra1 ra${suff1} --dec1 dec${suff1} --ra2 ${params.refcat_ra}${suff2} --dec2 ${params.refcat_dec}${suff2} \
               --plot
  ls *.fits
  """
  else
  """
  echo ${task.process} on \${HOSTNAME}
  ln -s ${basename}.fits ${basename}_warped.fits
  ls *.fits
  """
}


process make_mean_image {
  input:
  path image

  output:
  tuple val('mean'), path('mean.fits')

  script:
  """
  #!/usr/bin/env python

  from astropy.io import fits
  import sys
  import socket

  print(f"${task.process} on {socket.gethostname()}")
  files = ["${image.join('","')}"]
  if len(files) < 2:
      print("not enough files, need at least 2 to make a mean image")
      print("given {0}".format(files))
      sys.exit(1)

  print(f"Reading {files[0]}")
  hdu = fits.open(files[0])
  data = hdu[0].data

  for f in files[1:]:
      print(f"Adding {f}")
      data += fits.getdata(f)
  data /= len(files)

  hdu[0].data = data
  hdu.writeto("mean.fits")
  print("Wrote mean.fits")
  """
}


process bane_mean_image {
  label 'bane'

  input:
  tuple val(basename), path(mean)

  output:
  tuple val(basename), path(mean), path("${basename}_{bkg,rms}.fits")

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  BANE --cores ${task.cpus} ${mean}
  """
}


process sfind_mean_image {
  label 'aegean'

  input:
  tuple val(basename), path(mean), path(bkg_rms_fits)

  output:
  path "persistent_sources.fits"

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  aegean --cores ${task.cpus} --background *_bkg.fits --noise *_rms.fits --table ${mean} ${region_command} ${mean}
  ${monitoring_command}
  """
}


process source_monitor {
  label 'aegean'

  input:
  path mean_cat
  tuple val(basename), path(image)

  output:
  tuple path("${basename}_comp.fits"), path(image, includeInputs:true)
  path "${basename}_comp.fits"

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  aegean --cores ${task.cpus} --background *_bkg.fits --noise *_rms.fits --noregroup\
         --table ${basename}.fits --priorized 1 --input ${mean_cat} ${basename}.fits

  # super hack to get stilts to play nice and add two columns of strings
  epoch=\$(${params.codeDir}get_epoch.py ${basename}.fits)
  epoch="\\\\\\\"\${epoch}\\\\\\\""
  filename="\\\\\\\"${basename}.fits\\\\\\\""
  ${params.stilts} tpipe in=${basename}_comp.fits cmd="addcol image \${filename}" \
                                                  cmd="addcol epoch \${epoch}" \
                                                  ofmt=fits out=temp.fits
  mv temp.fits ${basename}_comp.fits
  """
}


process join_fluxes {
  label 'python'

  input:
  path source_monitor_cat
  path reference_fits

  output:
  path "flux_table.vot"

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  ls
  ls *_comp.fits > epochs.txt
  ${params.codeDir}join_catalogues.py --refcat ${reference_fits} --epochs epochs.txt --out flux_table.vot
  """
}


process compute_stats {
  label 'python'

  input:
  path flux_table

  output:
  tuple path("flux_table.vot", includeInputs:true), path("stats_table.vot")

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  ls
  NDOF=(\$(${params.codeDir}auto_corr.py --table ${flux_table}))
  echo \${NDOF[@]}
  echo \${NDOF[@]} > NDOF.txt
  ${params.codeDir}calc_var.py --table flux_table.vot --ndof \${NDOF[-1]} --out stats_table.vot --cores ${task.cpus}
  """
}


process plot_lc {
  label 'python'

  input:
  tuple path(flux_table), path(stats_table)

  output:
  path 'plots'

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  mkdir plots
  ${params.codeDir}plot_variables.py --ftable ${flux_table} --stable ${stats_table} --plot plots/variables.png --all --cores ${task.cpus}
  """
}


process mask_images {
  label 'python'

  input:
  path mean_cat
  tuple val(basename), path(warped_images)

  output:
  tuple val("${basename}_masked"), path("*.fits", includeInputs:true)

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  ls *.fits
  AeRes -c ${mean_cat} -f *_warped.fits -r ${basename}_masked.fits --mask --sigma 0.1
  """
}


process sfind_masked {
  label 'aegean'

  input:
  tuple val(basename), path(masked_images)

  output:
  path "${basename}_comp.fits" optional true

  script:
  """
  echo ${task.process} on  \${HOSTNAME}
  ls *
  aegean --cores ${task.cpus} --background *_bkg.fits --noise *_rms.fits --table ${basename}.fits ${basename}.fits ${region_command}
  # Don't filter if there is no output
  if [[ -e ${basename}_comp.fits ]]
  then
    ${params.codeDir}filter_transients.py --incat ${basename}_comp.fits --image ${basename}.fits --outcat out.fits
    if [[ -e out.fits ]]
    then
      mv out.fits ${basename}_comp.fits
    fi
  fi
  ls *.fits
  """
}


process compile_transients_candidates {
  label 'python'

  input:
  path catalogue

  output:
  path 'transients.fits'

  script:
  """
  echo ${task.process} on \${HOSTNAME}
  ls *_comp.fits > temp.dat
  ${params.codeDir}collect_transients.py --infile temp.dat --out transients.fits --ignoremissing
  """
}


process transients_plot {
  label 'python'

  input:
  path transients

  output:
  path 'transients.png'

  script:
  """
  #! /usr/bin/env python

  from astropy.table import Table
  import numpy as np
  import matplotlib
  from matplotlib import pyplot
  from matplotlib.patches import Ellipse
  import socket

  print(f"${task.process} on {socket.gethostname()}")

  tab = Table.read("${transients}")
  nepochs = np.max(tab['epoch'])*1.
  kwargs={'fontsize':14}

  cmap = pyplot.cm.plasma_r
  # define the bins and normalize
  bounds = np.linspace(3,15,13)
  norm = matplotlib.colors.BoundaryNorm(bounds, cmap.N)

  fig = pyplot.figure(figsize=(8,7))
  ax = fig.add_subplot(1,1,1)
  cax = ax.scatter(tab['ra'],tab['dec'],
                    c=tab['peak_flux']/tab['local_rms'],
                    cmap=cmap, norm=norm, zorder=100)
  for r in tab:
      ax.add_patch(Ellipse((r['ra'],r['dec']),
                            width=0.5, height=3, angle=r['epoch']/nepochs*360,
                            alpha=0.35, edgecolor='none',
                            color=cmap(norm(r['peak_flux']/r['local_rms'])),
                            zorder=norm(r['peak_flux']/r['local_rms'])
                          ))

  cb = fig.colorbar(cax,ax=ax)
  cb.set_ticks(range(3,16,2))
  cb.set_label("SNR", **kwargs)
  ax.set_xlabel("RA J2000",**kwargs)
  ax.set_ylabel("Dec J2000", **kwargs)
  # flip the x axis so that RA increases to the left
  ax.set_xlim((ax.get_xlim()[1],ax.get_xlim()[0]))
  ax.grid()
  pyplot.savefig("transients.png")
  """
}


workflow {
  bane_raw( image_ch )
  initial_sfind( bane_raw.out )
  fits_warp( initial_sfind.out,
             Channel.fromPath( params.ref_catalogue ) )
  make_mean_image( fits_warp.out[0].collect() )
  bane_mean_image( make_mean_image.out )
  sfind_mean_image( bane_mean_image.out )
  source_monitor( sfind_mean_image.out,
                  fits_warp.out[1] )
  join_fluxes( source_monitor.out[1].collect(),
               sfind_mean_image.out )
  compute_stats( join_fluxes.out )
  plot_lc( compute_stats.out )
  mask_images( sfind_mean_image.out,
               fits_warp.out[1] )
  sfind_masked( mask_images.out )
  compile_transients_candidates( sfind_masked.out.collect() )
  transients_plot( compile_transients_candidates.out )
}