#' @title Import Data into Sirius
#'
#' @name import
#' @export
#'
#' @param ms1Spectra `Spectra`, the MS1 spectra to import.
#' @param ms2Spectra `Spectra`, the MS2 spectra to import.
#' @param sirius `Sirius`, the connection to the Sirius instance with a
#'        loaded project
#'
#' @param adducts `character` vector of the adduct(s) known to refer to the
#'        features that are being imported. Needs to be of either length 1 or
#'        the same length as the number of features being imported. If of
#'        length 1, and less than the number of features being imported, the
#'        same adduct will be used for all features.
#'
#' @param deleteExistingFeatures `logical(1)`, if `TRUE`, all existing features
#'        will be deleted before importing the new ones.
#'
#'
#' @importFrom methods setClass new
#' @importClassesFrom ProtGenerics Param
#'
#' @importFrom Rsirius FeatureImport BasicSpectrum SimplePeak
#' @importFrom Spectra spectraData peaksData
#'
NULL

#' @rdname import
#' @export
import <- function(sirius, ms1Spectra, ms2Spectra,
                   adducts = character(), deleteExistingFeatures = TRUE) {
    id_field <- if ("feature_id" %in% colnames(spectraData(ms1Spectra))) {
        "feature_id"
    } else if ("chrom_peak_id" %in% colnames(spectraData(ms1Spectra))) {
        "chrom_peak_id"
    } else "spectra_id"
    if (!length(adducts)) adducts <- "[M+?]+" # or have it as the default.
    if (length(adducts) != length(unique(ms1Spectra[[id_field]]))) {
        if (length(adducts) == 1)
            adducts <- rep(adducts,
                           length(unique(ms1Spectra[[id_field]])))
        else
            stop("The number of adducts must be either 1 or the same as the ",
                 "number of features being imported.")
    }
    if (deleteExistingFeatures) sirius <- deleteFeatures(sirius)
    fts <- .process_feature_import(sirius = sirius,
                                   ms1Spectra = ms1Spectra,
                                   ms2Spectra = ms2Spectra,
                                   id_field = id_field,
                                   adducts = adducts)
    .upload_feature_import(sirius = sirius, allFeatures = fts)
    sirius@featureMap <- mapFeatures(sirius = sirius)
    sirius
}

#' @noRd
#' @param id_field `character(1)`, either "feature_id" or "chrom_peak_id", will
#'        be used to determine the metadata to be used for the feature import.
.upload_feature_import <- function(sirius, allFeatures) {
    sirius@api$features_api$AddAlignedFeatures(
        project_id = sirius@projectId,
        allFeatures
    )
}

.process_feature_import <- function(sirius, ms1Spectra, ms2Spectra,
                                    id_field, adducts) {
    unmatched_ids <- setdiff(unique(ms1Spectra[[id_field]]),
                             unique(ms2Spectra[[id_field]]))
    if (length(unmatched_ids) > 0) {
        stop("The following IDs are unmatched in ms1Spectra and ms2Spectra: ",
             paste(unmatched_ids, collapse = ", "))
    }
    allfts <- unique(ms1Spectra[[id_field]])
    allFeatures <- Map(function(fts, adduct) {
        print(fts)
        ms1_tmp <- ms1Spectra[ms1Spectra[[id_field]] == fts]
        ms2_tmp <- ms2Spectra[ms2Spectra[[id_field]] == fts]
        .createFeatureImport(feature_id = fts,
                             ms1_tmp = ms1_tmp,
                             ms2_tmp = ms2_tmp,
                             id_field = id_field,
                             adduct = adduct)
    }, allfts, adducts)
    allFeatures
}

# Create a FeatureImport object
.createFeatureImport <- function(feature_id, ms1_tmp, ms2_tmp, id_field,
                                 adduct) {
    ms1_processed <- .processSpectra(ms1_tmp) # slow
    ms2_processed <- .processSpectra(ms2_tmp) # super fast
    if (id_field == "spectra_id") {
        mtd <- spectraData(ms1_tmp)[1,
                                       c("spectra_mzmed", "polarity")]

        if (mtd$polarity == 0) mtd$polarity <- -1
        return(FeatureImport$new(
            externalFeatureId = as.character(feature_id),
            ionMass = mtd[[1]],
            charge = mtd[[2]],
            detectedAdducts = list(adduct),
            ms1Spectra = ms1_processed,
            ms2Spectra = ms2_processed
        ))
    }
    if (id_field == "feature_id")
        mtd <- spectraData(ms1_tmp)[1,
                                       c("feature_mzmed", "polarity",
                                         "feature_rtmin",
                                         "feature_rtmax", "feature_rtmed")]
    else
        mtd <- spectraData(ms1_tmp)[1,
                                       c("chrom_peak_mz", "polarity",
                                         "chrom_peak_rtmin",
                                         "chrom_peak_rtmax", "chrom_peak_rt")]
    if (mtd$polarity == 0) mtd$polarity <- -1
    FeatureImport$new(
        externalFeatureId = feature_id,
        ionMass = mtd[[1]],
        charge = mtd[[2]],
        rtStartSeconds = mtd[[3]],
        rtEndSeconds = mtd[[4]],
        rtApexSeconds = mtd[[5]],
        detectedAdducts = list(adduct),
        ms1Spectra = ms1_processed,
        ms2Spectra = ms2_processed
    )
}

# Helper function to process spectra
.processSpectra <- function(spectra) {
    lapply(seq_along(spectra), function(i) {
        .createBasicSpectrum(
            spectrum_data = peaksData(spectra)[[i]],
            spectrum_metadata = spectraData(spectra)[i, ])
    })
}

# Create a BasicSpectrum object
.createBasicSpectrum <- function(spectrum_data, spectrum_metadata) {
    peaks <- lapply(seq_len(nrow(spectrum_data)), function(x) {
        SimplePeak$new(mz = spectrum_data[x, "mz"],
                       intensity = spectrum_data[x, "intensity"])
    })
    BasicSpectrum$new(
        msLevel = spectrum_metadata$msLevel,
        scanNumber = spectrum_metadata$scanIndex,
        precursorMz = if (spectrum_metadata$msLevel == 2) spectrum_metadata$precursorMz else NULL,
        collisionEnergy = if (!is.na(spectrum_metadata$collisionEnergy) && spectrum_metadata$collisionEnergy != 0)
            as.character(spectrum_metadata$collisionEnergy) else NULL,
        peaks = peaks
    )
}
