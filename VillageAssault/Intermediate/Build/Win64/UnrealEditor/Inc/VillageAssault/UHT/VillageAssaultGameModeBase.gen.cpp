// Copyright Epic Games, Inc. All Rights Reserved.
/*===========================================================================
	Generated code exported from UnrealHeaderTool.
	DO NOT modify this manually! Edit the corresponding .h files instead!
===========================================================================*/

#include "UObject/GeneratedCppIncludes.h"
#include "VillageAssault/VillageAssaultGameModeBase.h"
PRAGMA_DISABLE_DEPRECATION_WARNINGS
void EmptyLinkFunctionForGeneratedCodeVillageAssaultGameModeBase() {}
// Cross Module References
	ENGINE_API UClass* Z_Construct_UClass_AGameModeBase();
	UPackage* Z_Construct_UPackage__Script_VillageAssault();
	VILLAGEASSAULT_API UClass* Z_Construct_UClass_AVillageAssaultGameModeBase();
	VILLAGEASSAULT_API UClass* Z_Construct_UClass_AVillageAssaultGameModeBase_NoRegister();
// End Cross Module References
	void AVillageAssaultGameModeBase::StaticRegisterNativesAVillageAssaultGameModeBase()
	{
	}
	IMPLEMENT_CLASS_NO_AUTO_REGISTRATION(AVillageAssaultGameModeBase);
	UClass* Z_Construct_UClass_AVillageAssaultGameModeBase_NoRegister()
	{
		return AVillageAssaultGameModeBase::StaticClass();
	}
	struct Z_Construct_UClass_AVillageAssaultGameModeBase_Statics
	{
		static UObject* (*const DependentSingletons[])();
#if WITH_METADATA
		static const UECodeGen_Private::FMetaDataPairParam Class_MetaDataParams[];
#endif
		static const FCppClassTypeInfoStatic StaticCppClassTypeInfo;
		static const UECodeGen_Private::FClassParams ClassParams;
	};
	UObject* (*const Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::DependentSingletons[])() = {
		(UObject* (*)())Z_Construct_UClass_AGameModeBase,
		(UObject* (*)())Z_Construct_UPackage__Script_VillageAssault,
	};
#if WITH_METADATA
	const UECodeGen_Private::FMetaDataPairParam Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::Class_MetaDataParams[] = {
		{ "Comment", "/**\n * \n */" },
		{ "HideCategories", "Info Rendering MovementReplication Replication Actor Input Movement Collision Rendering HLOD WorldPartition DataLayers Transformation" },
		{ "IncludePath", "VillageAssaultGameModeBase.h" },
		{ "ModuleRelativePath", "VillageAssaultGameModeBase.h" },
		{ "ShowCategories", "Input|MouseInput Input|TouchInput" },
	};
#endif
	const FCppClassTypeInfoStatic Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::StaticCppClassTypeInfo = {
		TCppClassTypeTraits<AVillageAssaultGameModeBase>::IsAbstract,
	};
	const UECodeGen_Private::FClassParams Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::ClassParams = {
		&AVillageAssaultGameModeBase::StaticClass,
		"Game",
		&StaticCppClassTypeInfo,
		DependentSingletons,
		nullptr,
		nullptr,
		nullptr,
		UE_ARRAY_COUNT(DependentSingletons),
		0,
		0,
		0,
		0x009002ACu,
		METADATA_PARAMS(Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::Class_MetaDataParams, UE_ARRAY_COUNT(Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::Class_MetaDataParams))
	};
	UClass* Z_Construct_UClass_AVillageAssaultGameModeBase()
	{
		if (!Z_Registration_Info_UClass_AVillageAssaultGameModeBase.OuterSingleton)
		{
			UECodeGen_Private::ConstructUClass(Z_Registration_Info_UClass_AVillageAssaultGameModeBase.OuterSingleton, Z_Construct_UClass_AVillageAssaultGameModeBase_Statics::ClassParams);
		}
		return Z_Registration_Info_UClass_AVillageAssaultGameModeBase.OuterSingleton;
	}
	template<> VILLAGEASSAULT_API UClass* StaticClass<AVillageAssaultGameModeBase>()
	{
		return AVillageAssaultGameModeBase::StaticClass();
	}
	DEFINE_VTABLE_PTR_HELPER_CTOR(AVillageAssaultGameModeBase);
	AVillageAssaultGameModeBase::~AVillageAssaultGameModeBase() {}
	struct Z_CompiledInDeferFile_FID_Users_dillo_Repos_Village_Assault_VillageAssault_Source_VillageAssault_VillageAssaultGameModeBase_h_Statics
	{
		static const FClassRegisterCompiledInInfo ClassInfo[];
	};
	const FClassRegisterCompiledInInfo Z_CompiledInDeferFile_FID_Users_dillo_Repos_Village_Assault_VillageAssault_Source_VillageAssault_VillageAssaultGameModeBase_h_Statics::ClassInfo[] = {
		{ Z_Construct_UClass_AVillageAssaultGameModeBase, AVillageAssaultGameModeBase::StaticClass, TEXT("AVillageAssaultGameModeBase"), &Z_Registration_Info_UClass_AVillageAssaultGameModeBase, CONSTRUCT_RELOAD_VERSION_INFO(FClassReloadVersionInfo, sizeof(AVillageAssaultGameModeBase), 2802681912U) },
	};
	static FRegisterCompiledInInfo Z_CompiledInDeferFile_FID_Users_dillo_Repos_Village_Assault_VillageAssault_Source_VillageAssault_VillageAssaultGameModeBase_h_3291621024(TEXT("/Script/VillageAssault"),
		Z_CompiledInDeferFile_FID_Users_dillo_Repos_Village_Assault_VillageAssault_Source_VillageAssault_VillageAssaultGameModeBase_h_Statics::ClassInfo, UE_ARRAY_COUNT(Z_CompiledInDeferFile_FID_Users_dillo_Repos_Village_Assault_VillageAssault_Source_VillageAssault_VillageAssaultGameModeBase_h_Statics::ClassInfo),
		nullptr, 0,
		nullptr, 0);
PRAGMA_ENABLE_DEPRECATION_WARNINGS
